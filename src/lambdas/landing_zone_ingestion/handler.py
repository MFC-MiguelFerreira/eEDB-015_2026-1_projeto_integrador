"""
Lambda: Landing Zone Ingestion
===============================
Faz o download dos arquivos CSV do dataset Health Insurance Marketplace
(Kaggle) e os armazena no bucket de Landing Zone sem nenhuma modificação.

Fluxo esperado:
    1. Receber o evento (manual, EventBridge ou Step Functions)
    2. Autenticar na API do Kaggle via credenciais no SSM Parameter Store
    3. Baixar cada arquivo CSV para /tmp (armazenamento efêmero da Lambda)
    4. Fazer upload para s3://{LANDING_BUCKET}/{filename}
    5. Retornar sumário da operação

Variáveis de Ambiente (definidas no CloudFormation):
    LANDING_BUCKET  — nome do bucket S3 de Landing Zone
    LOG_LEVEL       — nível de log (padrão: INFO)

TODO: Implementar a lógica de download do Kaggle
"""

import json
import logging
import os

import boto3

# ---------------------------------------------------------------------------
# Configuração de logging
# ---------------------------------------------------------------------------
log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, log_level, logging.INFO))

# ---------------------------------------------------------------------------
# Clientes AWS (inicializados fora do handler para reuso entre invocações)
# ---------------------------------------------------------------------------
s3_client = boto3.client("s3")

# ---------------------------------------------------------------------------
# Configuração via variáveis de ambiente
# ---------------------------------------------------------------------------
LANDING_BUCKET = os.environ["LANDING_BUCKET"]


# ---------------------------------------------------------------------------
# Handler principal
# ---------------------------------------------------------------------------
def lambda_handler(event: dict, context) -> dict:
    """
    Ponto de entrada da Lambda.

    Parâmetros do evento (event):
        files (list[str], opcional):
            Lista de nomes de arquivos a baixar do dataset.
            Se não informado, todos os arquivos do dataset são baixados.

    Retorna:
        dict com statusCode (int) e body (JSON string) contendo o
        resultado da operação ou mensagem de erro.

    Exemplo de evento:
        {"files": ["Rate.zip", "PlanAttributes.zip"]}
    """
    logger.info("Iniciando ingestão na Landing Zone. Bucket: %s", LANDING_BUCKET)
    logger.info("Evento recebido: %s", json.dumps(event))

    # TODO: Implementar lógica de download do Kaggle
    # Sugestão de fluxo:
    #   1. Ler credenciais do Kaggle armazenadas no SSM Parameter Store
    #   2. Instanciar o cliente da API do Kaggle
    #   3. Determinar a lista de arquivos: event.get("files") ou listar todos
    #   4. Para cada arquivo:
    #       a. Baixar em streaming para /tmp (evita estourar memória)
    #       b. Fazer upload para s3://LANDING_BUCKET/<filename>
    #       c. Registrar nome, tamanho e ETag no sumário
    #   5. Retornar o sumário com os arquivos processados
"""
Lambda: Landing Zone Ingestion
===============================
Faz o download dos arquivos CSV do dataset Health Insurance Marketplace
(Kaggle) e os armazena no bucket de Landing Zone sem nenhuma modificação.

Fluxo esperado:
    1. Receber o evento (manual, EventBridge ou Step Functions)
    2. Autenticar na API do Kaggle via credenciais no SSM Parameter Store
    3. Baixar cada arquivo CSV para /tmp (armazenamento efêmero da Lambda)
    4. Fazer upload para s3://{LANDING_BUCKET}/{filename}
    5. Retornar sumário da operação
"""

import json
import logging
import os
import zipfile
import concurrent.futures

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
# Aumentamos o pool de conexões do boto3 para suportar o Multi-threading
boto_config = Config(max_pool_connections=20, retries={'max_attempts': 3})
aws_endpoint = os.environ.get("AWS_ENDPOINT_URL") # Permite rodar localmente no LocalStack

s3_client = boto3.client("s3", endpoint_url=aws_endpoint, config=boto_config)
ssm_client = boto3.client("ssm", endpoint_url=aws_endpoint, config=boto_config)

LANDING_BUCKET = os.environ["LANDING_BUCKET"]
KAGGLE_DATASET = "hhs/health-insurance-marketplace"

# Configuração de alta performance para o S3 (Upload em múltiplas partes)
s3_transfer_config = TransferConfig(max_concurrency=4, multipart_chunksize=8 * 1024 * 1024)

# ---------------------------------------------------------------------------
# Funções Auxiliares (Trabalhador Paralelo)
# ---------------------------------------------------------------------------
def process_single_csv(file_info, zip_path: str, bucket: str) -> dict:
    """Extrai um único ficheiro, envia para o S3 e apaga-o do /tmp para poupar espaço."""
    # Ignora ficheiros de sistema ou macOS lixo que possam vir no ZIP
    if file_info.filename.split('/')[-1].startswith('._') or '__MACOSX' in file_info.filename:
        return None

    logger.info(f"⚡ A extrair e a enviar: {file_info.filename}")
    
    with zipfile.ZipFile(zip_path, 'r') as zf:
        # Extrai APENAS este ficheiro para o /tmp
        extracted_path = zf.extract(file_info, "/tmp")
        
        # Mantém a estrutura de pastas do ZIP (se existir)
        s3_key = f"raw/health_insurance/{file_info.filename}"
        
        # Upload direto para o S3
        s3_client.upload_file(
            extracted_path, 
            bucket, 
            s3_key,
            Config=s3_transfer_config
        )
        
        # MICRO-LIMPEZA: Apaga o ficheiro imediatamente após o upload
        # Impede que os 12GB estoirem o limite de 10GB do /tmp
        os.remove(extracted_path)
        logger.info(f"✅ Sucesso: {s3_key}")
        
        return file_info.filename

# ---------------------------------------------------------------------------
# Handler principal
# ---------------------------------------------------------------------------
def lambda_handler(event: dict, context) -> dict:
    logger.info("Iniciando ingestão na Landing Zone. Bucket: %s", LANDING_BUCKET)
    
    try:
        # 1. Obter Credenciais Kaggle do SSM Parameter Store
        user_param = ssm_client.get_parameter(Name="/eedb015/kaggle/username", WithDecryption=True)
        key_param = ssm_client.get_parameter(Name="/eedb015/kaggle/key", WithDecryption=True)
        kaggle_user = user_param['Parameter']['Value']
        kaggle_key = key_param['Parameter']['Value']

        # 2. Download do ZIP do Kaggle (Streaming Chunked)
        url = f"https://www.kaggle.com/api/v1/datasets/download/{KAGGLE_DATASET}"
        zip_path = "/tmp/dataset.zip"
        
        logger.info("A descarregar o dataset (Streaming)...")
        response = requests.get(url, auth=(kaggle_user, kaggle_key), stream=True)
        response.raise_for_status()
        
        # Guarda em blocos de 2MB para não esgotar a RAM de 512MB da Lambda
        with open(zip_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=2 * 1024 * 1024):
                if chunk:
                    f.write(chunk)
        logger.info("Download do ZIP concluído.")

        # 3. Ler metadados do ZIP e filtrar ficheiros (se pedido no evento)
        with zipfile.ZipFile(zip_path, 'r') as zf:
            files_to_process = [f for f in zf.infolist() if f.filename.endswith('.csv')]
            
        files_requested = event.get("files")
        if files_requested:
            files_to_process = [f for f in files_to_process if f.filename in files_requested]

        # 4. Paralelismo (Fan-Out) para processar os CSVs muito rápido
        processed_files = []
        max_threads = 4 # 4 Threads é o ideal para o equilíbrio CPU/Rede na Lambda
        
        logger.info(f"A iniciar upload paralelo de {len(files_to_process)} ficheiros...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_threads) as executor:
            # Submete as tarefas para as threads
            futures = [
                executor.submit(process_single_csv, f_info, zip_path, LANDING_BUCKET) 
                for f_info in files_to_process
            ]
            
            # Recolhe os resultados à medida que vão terminando
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                if result:
                    processed_files.append(result)

        # 5. Limpeza final
        os.remove(zip_path)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Sucesso! {len(processed_files)} ficheiros ingeridos.",
                "bucket": LANDING_BUCKET,
                "arquivos": processed_files
            })
        }

    except Exception as e:
        logger.error(f"Erro fatal na ingestão: {str(e)}", exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Falha na ingestão.", "error": str(e)})
        }
