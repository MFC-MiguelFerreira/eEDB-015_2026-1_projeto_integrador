"""
Glue Job: Landing Zone → Bronze (Iceberg)
==========================================
Lê todos os CSVs da Landing Zone (prefixo raw/) e cria/atualiza tabelas Iceberg
no database Bronze. Uma tabela por tipo de arquivo, derivada do caminho S3.

Regras:
  - Dados não modificados: todos os campos lidos como string (inferSchema=false).
  - Colunas de metadados adicionadas: `landinzone_path`, `ingestion_datetime`.
  - Tabelas criadas ou substituídas via writeTo(...).createOrReplace().
  - Idempotente: re-executar recria a tabela com os dados mais recentes.

Mapeamento Landing → Bronze (exemplos):
  raw/health_insurance/Rate.csv            → {BRONZE_DATABASE}.rate
  raw/health_insurance/PlanAttributes.csv  → {BRONZE_DATABASE}.plan_attributes
  raw/health_insurance/raw/2014/Rate.csv   → {BRONZE_DATABASE}.raw_2014_rate

Parâmetros do Job (definidos como DefaultArguments no CloudFormation):
  --JOB_NAME           : nome do job Glue (obrigatório, injetado automaticamente)
  --PIPELINE_NAME      : nome do pipeline (ex: health_insurance); usado para derivar nomes de tabela
  --LANDING_ZONE_BUCKET: bucket S3 da Landing Zone onde os CSVs brutos estão armazenados
  --BRONZE_DATABASE    : nome do database Glue Catalog onde as tabelas Bronze serão criadas
"""

import logging
import re
import sys

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.conf import SparkConf
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("landing_to_bronze")

# ---------------------------------------------------------------------------
# Parâmetros do Job
# ---------------------------------------------------------------------------
args = getResolvedOptions(
    sys.argv, ["JOB_NAME", "PIPELINE_NAME", "LANDING_ZONE_BUCKET", "BRONZE_DATABASE"]
)

PIPELINE_NAME = args["PIPELINE_NAME"]
LANDING_ZONE_BUCKET = args["LANDING_ZONE_BUCKET"]
BRONZE_DATABASE = args["BRONZE_DATABASE"]

logger.info("Parâmetros do job carregados")
logger.info("  LANDING_ZONE_BUCKET  = %s", LANDING_ZONE_BUCKET)
logger.info("  BRONZE_DATABASE = %s", BRONZE_DATABASE)

# ---------------------------------------------------------------------------
# Inicialização Spark / Glue com extensões Iceberg
# ---------------------------------------------------------------------------
logger.info("Inicializando SparkContext com extensões Iceberg…")

scf = SparkConf()
scf.setAll([
    ("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"),
    ("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog"),
    ("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog"),
    ("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO"),
    ("spark.sql.defaultCatalog", "glue_catalog"),
    # Parser de datas legado (compatibilidade com dados históricos)
    ("spark.sql.legacy.timeParserPolicy", "LEGACY"),
    # Otimização de escrita no S3
    ("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2"),
    ("spark.speculation", "true"),
    # Sobrescrita dinâmica de partições
    ("spark.sql.sources.partitionOverwriteMode", "dynamic"),
])

sc = SparkContext(conf=scf)
glue_ctx = GlueContext(sc)
spark = glue_ctx.spark_session

job = Job(glue_ctx)
job.init(args["JOB_NAME"], args)

logger.info("SparkContext e GlueContext inicializados com sucesso.")

# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------

def camel_to_snake(name: str) -> str:
    """
    Converte CamelCase para snake_case.
    Exemplo: "BenefitsCostSharing" → "benefits_cost_sharing"
    """
    s1 = re.sub("(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub("([a-z0-9])([A-Z])", r"\1_\2", s1).lower()


def s3_path_to_table_name(s3_key: str) -> str:
    """
    Converte um caminho S3 em nome de tabela snake_case, removendo o prefixo
    do pipeline para manter nomes curtos e legíveis no Glue Catalog.

    Exemplos (com PIPELINE_NAME="health_insurance"):
      raw/health_insurance/Rate.csv              → rate
      raw/health_insurance/PlanAttributes.csv    → plan_attributes
      raw/health_insurance/raw/2014/Rate_PUF.csv → raw_2014_rate_puf
    """
    # Remove extensão .csv
    path_without_ext = re.sub(r"\.csv$", "", s3_key, flags=re.IGNORECASE)

    # Divide o caminho em partes e converte cada uma para snake_case
    parts = path_without_ext.split("/")
    snake_parts = [camel_to_snake(part) for part in parts]

    table_name = "_".join(snake_parts)
    table_name = table_name.replace("-", "_")
    # Colapsa underscores consecutivos (ex: duplo __ vindo de datas)
    table_name = re.sub(r"_+", "_", table_name)

    # Remove o prefixo do pipeline para encurtar o nome da tabela
    pipeline_snake = camel_to_snake(PIPELINE_NAME)
    prefix_to_remove = f"raw_{pipeline_snake}_"
    table_name = table_name.replace(prefix_to_remove, "")

    return table_name


# ---------------------------------------------------------------------------
# Descoberta dos arquivos CSV na Landing Zone
# ---------------------------------------------------------------------------
logger.info("Iniciando descoberta de arquivos CSV no bucket '%s' (prefixo: raw/)…", LANDING_ZONE_BUCKET)

s3 = boto3.client("s3")
paginator = s3.get_paginator("list_objects_v2")

# file_groups: table_name → lista de s3_paths
file_groups: dict[str, list[str]] = {}

for page in paginator.paginate(Bucket=LANDING_ZONE_BUCKET, Prefix="raw/"):
    for obj in page.get("Contents", []):
        key = obj["Key"]

        if not key.lower().endswith(".csv"):
            continue

        table_name = s3_path_to_table_name(key)
        s3_path = f"s3://{LANDING_ZONE_BUCKET}/{key}"
        file_groups.setdefault(table_name, []).append(s3_path)

        logger.debug("  Arquivo mapeado: %-60s → %s", key, table_name)

logger.info(
    "Descoberta concluída: %d tipo(s) de tabela encontrado(s): %s",
    len(file_groups),
    sorted(file_groups.keys()),
)

if not file_groups:
    logger.warning("Nenhum arquivo CSV encontrado na Landing Zone. Encerrando job.")
    job.commit()
    sys.exit(0)

# ---------------------------------------------------------------------------
# Processamento: uma tabela Iceberg por tipo de arquivo
# ---------------------------------------------------------------------------
tables_ok: list[str] = []
tables_failed: list[str] = []

for table_name, s3_paths in sorted(file_groups.items()):
    bronze_table = f"{BRONZE_DATABASE}.{table_name}"
    logger.info("Processando tabela '%s' (%d arquivo(s))…", bronze_table, len(s3_paths))

    try:
        df = (
            spark.read.csv(
                path=s3_paths,
                header=True,
                inferSchema=False,
                encoding="UTF-8",
            )
            # Metadados de rastreabilidade
            .withColumn("landinzone_path", F.lit(s3_paths[0]))
            .withColumn("ingestion_datetime", F.to_utc_timestamp(F.current_timestamp(), "UTC"))
        )
        df.printSchema()

        logger.info(
            "  Leitura concluída: Escrevendo em '%s'…",
            bronze_table,
        )

        df.writeTo(bronze_table).createOrReplace()

        logger.info("  Tabela '%s' criada/atualizada com sucesso.", bronze_table)
        tables_ok.append(bronze_table)

    except Exception as exc:  # noqa: BLE001
        logger.error(
            "  ERRO ao processar tabela '%s': %s",
            bronze_table,
            exc,
            exc_info=True,
        )
        tables_failed.append(bronze_table)

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
logger.info("=" * 70)
logger.info("Job concluído.")
logger.info("  Tabelas processadas com sucesso : %d — %s", len(tables_ok), tables_ok)
if tables_failed:
    logger.error("  Tabelas com falha               : %d — %s", len(tables_failed), tables_failed)
logger.info("=" * 70)

job.commit()
