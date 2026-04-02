"""
Glue Job: Landing Zone → Bronze (Iceberg)
==========================================
Lê os CSVs da Landing Zone e cria/atualiza tabelas Iceberg no database Bronze.
Uma tabela por tipo de arquivo (rate, plan_attributes, service_area, ...).

Regras:
  - Dados não modificados: todos os campos lidos como string (inferSchema=false).
  - Coluna `year` (int) adicionada a partir do caminho do arquivo — não existe no CSV.
  - Tabelas particionadas por `year`, compressão Snappy, formato Iceberg v2.
  - Idempotente: re-executar para o mesmo ano sobrescreve apenas aquela partição.

Mapeamento Landing → Bronze:
  raw/health_insurance/2014/Rate.csv            → eedb015_bronze.rate           (year=2014)
  raw/health_insurance/2015/Rate.csv            → eedb015_bronze.rate           (year=2015)
  raw/health_insurance/2014/PlanAttributes.csv  → eedb015_bronze.plan_attributes (year=2014)
  ...

Parâmetros do Job (definidos como DefaultArguments no CloudFormation):
  --LANDING_BUCKET   : nome do bucket Landing Zone (obrigatório)
  --BRONZE_BUCKET    : nome do bucket Bronze — warehouse Iceberg (obrigatório)
  --BRONZE_DATABASE  : nome do Glue database Bronze, ex: eedb015_bronze (obrigatório)
  --YEAR             : reprocessa apenas este ano, ex: 2014 (opcional)
"""

import re
import sys
from functools import reduce

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import DataFrame
from pyspark.sql import functions as F

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------
args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "LANDING_BUCKET", "BRONZE_BUCKET", "BRONZE_DATABASE"],
)

# Parâmetro opcional: filtra apenas um ano específico
YEAR_FILTER: str | None = None
if "--YEAR" in sys.argv:
    YEAR_FILTER = getResolvedOptions(sys.argv, ["YEAR"])["YEAR"]

sc = SparkContext()
glue_ctx = GlueContext(sc)
spark = glue_ctx.spark_session
job = Job(glue_ctx)
job.init(args["JOB_NAME"], args)

# Com --datalake-formats iceberg (configurado no CloudFormation), o Glue 4.0
# registra automaticamente o catálogo 'glue_catalog'. Basta apontar o warehouse.
spark.conf.set(
    "spark.sql.catalog.glue_catalog.warehouse",
    f"s3://{args['BRONZE_BUCKET']}/",
)

LANDING_BUCKET = args["LANDING_BUCKET"]
BRONZE_DB = args["BRONZE_DATABASE"]

# ---------------------------------------------------------------------------
# Descoberta dos arquivos CSV na Landing Zone
# ---------------------------------------------------------------------------
s3 = boto3.client("s3")
paginator = s3.get_paginator("list_objects_v2")

# file_groups: table_name → lista de (year, s3_path)
file_groups: dict[str, list[tuple[str, str]]] = {}

for page in paginator.paginate(Bucket=LANDING_BUCKET, Prefix="raw/health_insurance/"):
    for obj in page.get("Contents", []):
        key = obj["Key"]

        # Padrão esperado: raw/health_insurance/YYYY/NomeArquivo.csv
        match = re.match(
            r"raw/health_insurance/(\d{4})/([^/]+)\.csv$", key, re.IGNORECASE
        )
        if not match:
            continue

        year, filename = match.group(1), match.group(2)
        if YEAR_FILTER and year != YEAR_FILTER:
            continue

        # CamelCase → snake_case para nome da tabela Glue
        # "PlanAttributes" → "plan_attributes", "Rate" → "rate"
        table_name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", filename).lower()
        file_groups.setdefault(table_name, []).append(
            (year, f"s3://{LANDING_BUCKET}/{key}")
        )

print(
    f"[bronze] {len(file_groups)} tipo(s) de arquivo encontrado(s): "
    f"{sorted(file_groups.keys())}"
)

if not file_groups:
    print("[bronze] Nenhum arquivo encontrado na Landing Zone. Encerrando.")
    job.commit()
    sys.exit(0)

# ---------------------------------------------------------------------------
# Processamento: uma tabela Iceberg por tipo de arquivo
# ---------------------------------------------------------------------------
for table_name, files in sorted(file_groups.items()):
    print(f"\n[bronze] Tabela '{table_name}' — {len(files)} arquivo(s)")
    full_table = f"glue_catalog.{BRONZE_DB}.{table_name}"

    # --- Leitura ---
    # Cada ano é lido individualmente e recebe a coluna `year`.
    # inferSchema=false garante que nenhum dado seja alterado por coerção de tipo.
    yearly_dfs: list[DataFrame] = []
    for year, path in sorted(files):
        df = (
            spark.read.option("header", "true")
            .option("inferSchema", "false")
            .option("encoding", "UTF-8")
            .csv(path)
        )
        df = df.withColumn("year", F.lit(year).cast("int"))
        print(f"  - {year}: {df.count()} linhas, {len(df.columns)} colunas")
        yearly_dfs.append(df)

    # Une todos os anos; colunas ausentes num ano específico recebem null
    combined_df: DataFrame = reduce(
        lambda a, b: a.unionByName(b, allowMissingColumns=True),
        yearly_dfs,
    )

    # --- Escrita Iceberg ---
    table_exists = spark.catalog.tableExists(full_table)

    if not table_exists:
        # Primeira carga: cria a tabela com particionamento e propriedades Iceberg
        (
            combined_df.writeTo(full_table)
            .tableProperty("write.parquet.compression-codec", "snappy")
            .tableProperty("format-version", "2")
            # Remove arquivos de metadados antigos automaticamente para economizar S3
            .tableProperty("write.metadata.delete-after-commit.enabled", "true")
            .tableProperty("write.metadata.previous-versions-max", "3")
            .partitionedBy(F.col("year"))
            .create()
        )
        print(f"  → Tabela '{full_table}' criada.")
    else:
        # Reprocessamento: sobrescreve apenas as partições presentes no DataFrame
        # (partições de outros anos não são tocadas — comportamento idempotente)
        combined_df.writeTo(full_table).overwritePartitions()
        years_processed = [y for y, _ in files]
        print(
            f"  → Partição(ões) {years_processed} sobrescrita(s) em '{full_table}'."
        )

job.commit()
print("\n[bronze] Job concluído com sucesso.")
