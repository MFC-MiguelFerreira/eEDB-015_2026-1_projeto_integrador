"""
Lambda: Landing Zone Ingestion
===============================
Faz o download dos arquivos CSV do dataset Health Insurance Marketplace
(Kaggle) e os armazena no bucket de Landing Zone sem nenhuma modificação.

Fluxo esperado:
    1. Receber o evento (manual, EventBridge ou Step Functions)
    2. Autenticar na API do Kaggle via credenciais no SSM Parameter Store
    3. Baixar o dataset completo (ZIP) via streaming para /tmp
    4. Extrair e fazer upload de cada CSV para s3://{LANDING_BUCKET}/raw/health_insurance/
    5. Retornar sumário da operação

Variáveis de Ambiente (definidas no CloudFormation):
    LANDING_BUCKET  — nome do bucket S3 de Landing Zone
    LOG_LEVEL       — nível de log (padrão: INFO)
    AWS_ENDPOINT_URL — endpoint alternativo para LocalStack (opcional)

Exemplo de evento:
    {}                                          → processa todos os CSVs
    {"files": ["2014/Rate.csv", "2014/PlanAttributes.csv"]}  → filtra arquivos específicos
"""

import concurrent.futures
import json
import logging
import os
import shutil
import tempfile
import zipfile

import boto3
import requests
from boto3.s3.transfer import TransferConfig
from botocore.config import Config

# ---------------------------------------------------------------------------
# Configuração de logging
# ---------------------------------------------------------------------------
log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, log_level, logging.INFO))

# ---------------------------------------------------------------------------
# Clientes AWS (com suporte transparente a LocalStack)
# ---------------------------------------------------------------------------
# Pool de conexões maior para suportar uploads paralelos
boto_config = Config(max_pool_connections=20, retries={"max_attempts": 3})
aws_endpoint = os.environ.get("AWS_ENDPOINT_URL")

s3_client = boto3.client("s3", endpoint_url=aws_endpoint, config=boto_config)
ssm_client = boto3.client("ssm", endpoint_url=aws_endpoint, config=boto_config)

LANDING_BUCKET = os.environ["LANDING_BUCKET"]
KAGGLE_DATASET = "hhs/health-insurance-marketplace"

# Upload em múltiplas partes para arquivos grandes
s3_transfer_config = TransferConfig(max_concurrency=4, multipart_chunksize=8 * 1024 * 1024)

# ---------------------------------------------------------------------------
# Funções Auxiliares
# ---------------------------------------------------------------------------
def process_single_csv(file_info, zip_path: str, bucket: str) -> str | None:
    """
    Extrai um único CSV do ZIP para um diretório temporário isolado,
    faz upload para o S3 e limpa o diretório ao final.

    Cada thread usa seu próprio diretório via tempfile.mkdtemp() para
    evitar race conditions na extração de arquivos com caminhos iguais.
    """
    filename = file_info.filename

    # Ignora arquivos de sistema/macOS
    if filename.split("/")[-1].startswith("._") or "__MACOSX" in filename:
        return None

    logger.info("Extraindo e enviando: %s", filename)

    # Diretório isolado por thread — evita colisões de escrita no /tmp
    temp_dir = tempfile.mkdtemp(dir="/tmp")

    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            extracted_path = zf.extract(file_info, temp_dir)

        s3_key = f"raw/health_insurance/{filename}"

        s3_client.upload_file(
            extracted_path,
            bucket,
            s3_key,
            Config=s3_transfer_config,
        )

        logger.info("Upload concluido: s3://%s/%s", bucket, s3_key)
        return filename

    finally:
        # Remove o diretório temporário independentemente de sucesso ou falha
        shutil.rmtree(temp_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Handler principal
# ---------------------------------------------------------------------------
def lambda_handler(event: dict, context) -> dict:
    logger.info("Iniciando ingestao na Landing Zone. Bucket: %s", LANDING_BUCKET)

    try:
        # 1. Obter credenciais do Kaggle no SSM Parameter Store
        user_param = ssm_client.get_parameter(Name="/eedb015/kaggle/username", WithDecryption=True)
        key_param = ssm_client.get_parameter(Name="/eedb015/kaggle/key", WithDecryption=True)
        kaggle_user = user_param["Parameter"]["Value"]
        kaggle_key = key_param["Parameter"]["Value"]

        # 2. Download do ZIP via streaming (blocos de 2 MB para não esgotar RAM)
        url = f"https://www.kaggle.com/api/v1/datasets/download/{KAGGLE_DATASET}"
        zip_path = "/tmp/dataset.zip"

        logger.info("Baixando dataset (streaming)...")
        response = requests.get(url, auth=(kaggle_user, kaggle_key), stream=True)
        response.raise_for_status()

        with open(zip_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=2 * 1024 * 1024):
                if chunk:
                    f.write(chunk)
        logger.info("Download do ZIP concluido.")

        # 3. Listar CSVs no ZIP e aplicar filtro opcional do evento
        with zipfile.ZipFile(zip_path, "r") as zf:
            files_to_process = [f for f in zf.infolist() if f.filename.endswith(".csv")]

        files_requested = event.get("files")
        if files_requested:
            files_to_process = [f for f in files_to_process if f.filename in files_requested]

        logger.info("Arquivos a processar: %d", len(files_to_process))

        # 4. Upload paralelo — cada thread opera em diretório isolado
        processed_files = []
        failed_files = []
        max_threads = 4

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_threads) as executor:
            future_to_file = {
                executor.submit(process_single_csv, f_info, zip_path, LANDING_BUCKET): f_info.filename
                for f_info in files_to_process
            }

            for future in concurrent.futures.as_completed(future_to_file):
                filename = future_to_file[future]
                try:
                    result = future.result()
                    if result:
                        processed_files.append(result)
                except Exception as exc:
                    # Registra a falha mas continua processando os demais arquivos
                    logger.error("Falha ao processar '%s': %s", filename, exc, exc_info=True)
                    failed_files.append(filename)

        # 5. Limpeza do ZIP original
        os.remove(zip_path)

        status_code = 200 if not failed_files else 207  # 207 = sucesso parcial
        return {
            "statusCode": status_code,
            "body": json.dumps({
                "message": f"{len(processed_files)} arquivo(s) ingerido(s), {len(failed_files)} falha(s).",
                "bucket": LANDING_BUCKET,
                "processados": processed_files,
                "falhas": failed_files,
            }),
        }

    except Exception as e:
        logger.error("Erro fatal na ingestao: %s", str(e), exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Falha na ingestao.", "error": str(e)}),
        }
