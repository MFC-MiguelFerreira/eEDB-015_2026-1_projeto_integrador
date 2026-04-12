"""
Glue Job: Bronze → Silver (Iceberg)
===================================
Lê todas as tabelas da camada Bronze no Glue Catalog, aplica limpezas e
transformações de tipagem e recria as tabelas correspondentes na camada Silver.

Regras principais:
  - Descobre automaticamente as tabelas do database Bronze.
  - Ignora tabelas com prefixo `raw_`.
  - Converte colunas textuais para tipos numéricos, booleanos e timestamp.
  - Trata valores como `No Charge` e `Not Applicable` durante os casts.
  - Aplica regras específicas para tabelas como `rate`, `plan_attributes` e
	`crosswalk`.
  - Recria a tabela Silver a cada execução para manter o schema consistente.

Parâmetros do Job:
  --JOB_NAME        : nome do job Glue (obrigatório, injetado automaticamente)
  --PIPELINE_NAME   : nome do pipeline (ex: health_insurance)
  --BRONZE_DATABASE : database Glue Catalog da camada Bronze
  --SILVER_DATABASE : database Glue Catalog da camada Silver
"""

import logging
import sys

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.conf import SparkConf
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
	level=logging.INFO,
	format="[%(asctime)s] %(levelname)s %(name)s — %(message)s",
	datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("bronze_to_silver")


# ---------------------------------------------------------------------------
# Parâmetros do Job
# ---------------------------------------------------------------------------
args = getResolvedOptions(
	sys.argv, ["JOB_NAME", "PIPELINE_NAME", "BRONZE_DATABASE", "SILVER_DATABASE"]
)

PIPELINE_NAME = args["PIPELINE_NAME"]
BRONZE_DATABASE = args["BRONZE_DATABASE"]
SILVER_DATABASE = args["SILVER_DATABASE"]

logger.info("Parâmetros do job carregados")
logger.info("  PIPELINE_NAME   = %s", PIPELINE_NAME)
logger.info("  BRONZE_DATABASE = %s", BRONZE_DATABASE)
logger.info("  SILVER_DATABASE = %s", SILVER_DATABASE)


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
	("spark.sql.legacy.timeParserPolicy", "LEGACY"),
	("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2"),
	("spark.speculation", "true"),
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
def list_catalog_tables(database_name: str) -> list[str]:
	"""Lista tabelas do Glue Catalog para um database, excluindo prefixos raw_."""
	glue = boto3.client("glue")
	paginator = glue.get_paginator("get_tables")

	table_names: list[str] = []
	for page in paginator.paginate(DatabaseName=database_name):
		for table in page.get("TableList", []):
			name = table["Name"]
			if not name.lower().startswith("raw_"):
				table_names.append(name)

	return sorted(table_names)


def parse_string_to_double(col_name: str):
	"""Converte string para double, tratando percentuais, moeda e nulos semânticos."""
	column = F.col(col_name)
	cleaned_numeric = F.regexp_replace(column, r"[\$,]", "")
	cleaned_percent = F.regexp_replace(column, r"[%,\s]", "")

	return (
		F.when(column.isin("No Charge", "no charge"), F.lit(0.0))
		.when(column.isin("Not Applicable", "not applicable"), F.lit(None).cast("double"))
		.when(column.contains("%"), cleaned_percent.cast("double") / 100.0)
		.otherwise(cleaned_numeric.cast("double"))
		.cast("double")
	)


def parse_string_to_boolean(col_name: str):
	"""Converte string para boolean com mapeamentos frequentes do dataset."""
	col_upper = F.upper(F.col(col_name))
	return (
		F.when(
			col_upper.isin("Y", "YES", "1", "TRUE", "COVERED", "NEW"),
			True,
		)
		.when(
			col_upper.isin("N", "NO", "0", "FALSE", "NOT COVERED", "EXISTING"),
			False,
		)
		.otherwise(None)
		.cast("boolean")
	)


def parse_string_to_timestamp(col_name: str):
	"""Converte string em timestamp no formato MM/dd/yyyy."""
	return F.to_timestamp(F.col(col_name), "MM/dd/yyyy").cast("timestamp")


def parse_string_to_integer(col_name: str):
	"""Converte string em inteiro, tratando `Not Applicable` como null."""
	return (
		F.when(
			F.col(col_name).isin("Not Applicable", "not applicable"),
			F.lit(None).cast("integer"),
		)
		.otherwise(F.col(col_name).cast("integer"))
		.cast("integer")
	)


def deduplicate_by_version(df, partition_cols):
	"""Mantém apenas o registro com maior VersionNum por chave lógica + PlanId."""
	window = Window.partitionBy(*partition_cols, "PlanId").orderBy(F.col("VersionNum").desc())
	return df.withColumn("rn", F.row_number().over(window)).filter("rn = 1").drop("rn")


def apply_transformations(table_name: str, df):
	"""Aplica transformações genéricas e específicas por tabela da Bronze."""
	double_cols = [
		"CopayInnTier1", "CopayInnTier2", "CopayOutofNet",
		"CoinsInnTier1", "CoinsInnTier2", "CoinsOutofNet",
		"IndividualRate", "IndividualTobaccoRate", "Couple",
		"PrimarySubscriberAndOneDependent", "PrimarySubscriberAndTwoDependents",
		"PrimarySubscriberAndThreeOrMoreDependents", "CoupleAndOneDependent",
		"CoupleAndTwoDependents", "CoupleAndThreeOrMoreDependents",
		"AvCalculatorOutputNumber", "DEHBCombInnOonFamilyMOOP", "DEHBCombInnOonIndividualMOOP",
		"DEHBDedCombInnOonFamily", "DEHBDedCombInnOonIndividual", "DEHBDedInnTier1Coinsurance",
		"DEHBDedInnTier1Family", "DEHBDedInnTier1Individual", "DEHBDedInnTier2Coinsurance",
		"DEHBDedInnTier2Family", "DEHBDedInnTier2Individual", "DEHBDedOutOfNetFamily",
		"DEHBDedOutOfNetIndividual", "DEHBInnTier1FamilyMOOP", "DEHBInnTier1IndividualMOOP",
		"DEHBOutOfNetFamilyMOOP", "DEHBOutOfNetIndividualMOOP", "EHBPediatricDentalApportionmentQuantity",
		"EHBPercentPremiumS4", "EHBPercentTotalPremium", "FirstTierUtilization", "HPID",
		"IndianPlanVariationEstimatedAdvancedPaymentAmountPerEnrollee", "IssuerActuarialValue",
		"MEHBCombInnOonFamilyMOOP", "MEHBCombInnOonIndividualMOOP", "MEHBDedCombInnOonFamily",
		"MEHBDedCombInnOonIndividual", "MEHBDedInnTier1Coinsurance", "MEHBDedInnTier1Family",
		"MEHBDedInnTier1Individual", "MEHBDedInnTier2Coinsurance", "MEHBDedInnTier2Family",
		"MEHBDedInnTier2Individual", "MEHBDedOutOfNetFamily", "MEHBDedOutOfNetIndividual",
		"MEHBInnTier1FamilyMOOP", "MEHBInnTier1IndividualMOOP", "MEHBInnTier2FamilyMOOP",
		"MEHBInnTier2IndividualMOOP", "MEHBOutOfNetFamilyMOOP", "MEHBOutOfNetIndividualMOOP",
		"SBCHavingDiabetesCoinsurance", "SBCHavingDiabetesCopayment", "SBCHavingDiabetesDeductible",
		"SBCHavingDiabetesLimit", "SBCHavingaBabyCoinsurance", "SBCHavingaBabyCopayment",
		"SBCHavingaBabyDeductible", "SBCHavingaBabyLimit", "SecondTierUtilization",
		"SpecialtyDrugMaximumCoinsurance", "TEHBCombInnOonFamilyMOOP", "TEHBCombInnOonIndividualMOOP",
		"TEHBDedCombInnOonFamily", "TEHBDedCombInnOonIndividual", "TEHBDedInnTier1Coinsurance",
		"TEHBDedInnTier1Family", "TEHBDedInnTier1Individual", "TEHBDedInnTier2Coinsurance",
		"TEHBDedInnTier2Family", "TEHBDedInnTier2Individual", "TEHBDedOutOfNetFamily",
		"TEHBDedOutOfNetIndividual", "TEHBInnTier1FamilyMOOP", "TEHBInnTier1IndividualMOOP",
		"TEHBInnTier2FamilyMOOP", "TEHBInnTier2IndividualMOOP", "TEHBOutOfNetFamilyMOOP",
		"TEHBOutOfNetIndividualMOOP",
	]
	for col_name in double_cols:
		if col_name in df.columns:
			df = df.withColumn(col_name, parse_string_to_double(col_name))

	timestamp_cols = [
		"ImportDate", "RateEffectiveDate", "RateExpirationDate",
		"PlanEffictiveDate", "PlanExpirationDate",
	]
	for col_name in timestamp_cols:
		if col_name in df.columns:
			df = df.withColumn(col_name, parse_string_to_timestamp(col_name))

	bool_cols = [
		"IsCovered", "IsEHB", "IsExclFromInnMOOP",
		"IsExclFromOonMOOP", "IsStateMandate",
		"IsSubjToDedTier1", "IsSubjToDedTier2", "QuantLimitOnSvc",
		"DomesticPartnerAsSpouseIndicator", "SameSexPartnerAsSpouseIndicator",
		"DentalOnlyPlan", "DentalPlan", "MultistatePlan_2014", "MultistatePlan_2015",
		"MultistatePlan_2016", "CoverEntireState", "PartialCounty", "IsHSAEligible",
		"IsNewPlan", "IsNoticeRequiredForPregnancy", "IsReferralRequiredForSpecialist",
		"UniquePlanDesign", "WellnessProgramOffered",
	]
	for col_name in bool_cols:
		if col_name in df.columns:
			df = df.withColumn(col_name, parse_string_to_boolean(col_name))

	int_cols = [
		"LimitQty", "BusinessYear", "MinimumStay",
		"MinimumTobaccoFreeMonthsRule", "DependentMaximumAgRule", "DependentMaximumAgeRule",
		"ChildAdultOnly_2014", "CrosswalkLevel", "ReasonForCrosswalk",
		"ChildAdultOnly_2015", "ChildAdultOnly_2016", "Age",
		"BeginPrimaryCareCostSharingAfterNumberOfVisits",
		"BeginPrimaryCareDeductibleCoinsuranceAfterNumberOfCopays",
		"BenefitPackageId", "InpatientCopaymentMaximumDays",
		"MedicalDrugDeductiblesIntegrated", "MedicalDrugMaximumOutofPocketIntegrated",
		"MultipleInNetworkTiers", "NationalNetwork", "OutOfCountryCoverage",
		"OutOfServiceAreaCoverage",
	]
	for col_name in int_cols:
		if col_name in df.columns:
			df = df.withColumn(col_name, parse_string_to_integer(col_name))

	if all(col_name in df.columns for col_name in ["BenefitName", "BusinessYear", "VersionNum"]):
		df = deduplicate_by_version(df, ["BenefitName", "BusinessYear"])

	return df


# ---------------------------------------------------------------------------
# Descoberta das tabelas Bronze
# ---------------------------------------------------------------------------
logger.info("Descobrindo tabelas no database Bronze '%s'…", BRONZE_DATABASE)
all_table_names = list_catalog_tables(BRONZE_DATABASE)
logger.info(
	"Descoberta concluída: %d tabela(s) elegível(is): %s",
	len(all_table_names),
	all_table_names,
)

if not all_table_names:
	logger.warning("Nenhuma tabela elegível encontrada na Bronze. Encerrando job.")
	job.commit()
	sys.exit(0)


# ---------------------------------------------------------------------------
# Garantia do database Silver
# ---------------------------------------------------------------------------
try:
	spark.sql(f"CREATE DATABASE IF NOT EXISTS {SILVER_DATABASE}")
	logger.info("Database '%s' criado/verificado.", SILVER_DATABASE)
except Exception as exc:  # noqa: BLE001
	logger.error("Erro ao criar database '%s': %s", SILVER_DATABASE, exc)
	raise


# ---------------------------------------------------------------------------
# Processamento Bronze → Silver
# ---------------------------------------------------------------------------
tables_ok: list[str] = []
tables_failed: list[str] = []

for table_name in all_table_names:
	bronze_table = f"{BRONZE_DATABASE}.{table_name}"
	silver_table = f"{SILVER_DATABASE}.{table_name}"
	logger.info("Processando tabela '%s' → '%s'…", bronze_table, silver_table)

	try:
		df = spark.table(bronze_table)
		logger.info("  Lida: %d coluna(s), %d linha(s) estimadas.", len(df.columns), df.count())

		df_transformed = apply_transformations(table_name, df)
		logger.info("  Transformada: %d coluna(s).", len(df_transformed.columns))

		try:
			spark.sql(f"DROP TABLE IF EXISTS {silver_table}")
			logger.info("  Tabela anterior removida.")
		except Exception as exc:  # noqa: BLE001
			logger.warning("  Aviso ao remover tabela anterior: %s", exc)

		df_transformed.writeTo(silver_table).createOrReplace()
		logger.info("  Tabela '%s' criada/atualizada com sucesso.", silver_table)

		try:
			df_final = spark.table(silver_table)
			logger.info("  Verificação: tabela criada com %d coluna(s).", len(df_final.columns))
		except Exception as exc:  # noqa: BLE001
			logger.warning("  Aviso na verificação da tabela: %s", exc)

		tables_ok.append(silver_table)

	except Exception as exc:  # noqa: BLE001
		logger.error(
			"  ERRO ao processar tabela '%s': %s",
			silver_table,
			exc,
			exc_info=True,
		)
		tables_failed.append(silver_table)


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
