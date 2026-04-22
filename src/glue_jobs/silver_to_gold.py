import sys
import time
import boto3
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, [
    'SQL_BUCKET',
    'SQL_PREFIX',
    'ATHENA_OUTPUT_BUCKET',
    'GOLD_DATABASE',
])

s3 = boto3.client('s3')
athena = boto3.client('athena')

SQL_BUCKET = args['SQL_BUCKET']
SQL_PREFIX = args['SQL_PREFIX'].rstrip('/')
ATHENA_OUTPUT = f"s3://{args['ATHENA_OUTPUT_BUCKET']}/gold-etl-output/"
GOLD_DATABASE = args['GOLD_DATABASE']

# Dimensões primeiro, depois fatos — respeita dependências lógicas do modelo estrela.
TABLES = [
    'dim_time',
    'dim_geography',
    'dim_issuer',
    'dim_benefit_category',
    'dim_network',
    'dim_plan',
    'fct_market_competition',
    'fct_plan_premium',
    'fct_benefit_coverage',
]


def read_sql(table):
    key = f"{SQL_PREFIX}/{table}.sql"
    obj = s3.get_object(Bucket=SQL_BUCKET, Key=key)
    return obj['Body'].read().decode('utf-8').strip()


def run_query(sql, label=""):
    resp = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={'Database': GOLD_DATABASE},
        ResultConfiguration={'OutputLocation': ATHENA_OUTPUT},
    )
    qid = resp['QueryExecutionId']
    while True:
        status = athena.get_query_execution(QueryExecutionId=qid)
        state = status['QueryExecution']['Status']['State']
        if state == 'SUCCEEDED':
            return
        if state in ('FAILED', 'CANCELLED'):
            reason = status['QueryExecution']['Status'].get('StateChangeReason', '—')
            raise RuntimeError(f"[{label}] Athena query {state}: {reason}")
        time.sleep(10)


for table in TABLES:
    print(f"[{table}] limpando tabela Iceberg...")
    run_query(f"DELETE FROM {GOLD_DATABASE}.{table}", f"DELETE {table}")

    print(f"[{table}] inserindo dados da Silver...")
    run_query(read_sql(table), f"INSERT {table}")

    print(f"[{table}] concluido.")

print("Camada Gold populada com sucesso.")
