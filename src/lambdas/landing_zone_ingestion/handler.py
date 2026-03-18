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

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Placeholder — lógica de download não implementada ainda.",
            "bucket": LANDING_BUCKET,
        }),
    }
