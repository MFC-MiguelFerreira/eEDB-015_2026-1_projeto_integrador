#!/usr/bin/env bash
# =============================================================================
# destroy_lambda.sh — Remove o stack CloudFormation da Lambda de ingestão
#
# Uso:
#   ./infrastructure/scripts/destroy_lambda.sh
#
# O que este script faz:
#   1. Remove o Stack 02 (Lambda + CloudWatch Log Group)
#   2. Apaga o pacote ZIP enviado ao bucket Landing Zone pelo deploy_lambda.sh
#      (esse arquivo NÃO é um recurso do CloudFormation e precisa de limpeza manual)
#
# Nota: este script NÃO remove o Stack 01 (buckets S3). Para remover toda a
# infraestrutura use destroy.sh 01-storage (depois de esvaziar os buckets).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Carrega credenciais do .env (se existir)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
  echo "Credenciais carregadas de $ENV_FILE"
fi

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STACK_01_NAME="eEDB015-01-storage"
STACK_02_NAME="eEDB015-02-lambda-ingestion"
S3_KEY="lambdas/landing-zone-ingestion/function.zip"

# ---------------------------------------------------------------------------
# Confirmação
# ---------------------------------------------------------------------------
echo "===================================================================="
echo " ATENÇÃO: esta ação é irreversível."
echo " Stack a remover: $STACK_02_NAME"
echo " Região         : $REGION"
echo ""
echo " Recursos que serão deletados:"
echo "   - Função Lambda de ingestão"
echo "   - CloudWatch Log Group da Lambda"
echo "   - Pacote ZIP em s3://.../$S3_KEY"
echo "===================================================================="
echo ""
read -r -p "Confirma a remoção? (digite 'sim' para continuar): " CONFIRM

if [[ "$CONFIRM" != "sim" ]]; then
  echo "Operação cancelada."
  exit 0
fi

# ---------------------------------------------------------------------------
# Passo 1: Remover o Stack 02
# ---------------------------------------------------------------------------
echo ""
echo "Removendo stack '$STACK_02_NAME'..."

aws cloudformation delete-stack \
  --region "$REGION" \
  --stack-name "$STACK_02_NAME"

echo "Aguardando remoção completa..."

aws cloudformation wait stack-delete-complete \
  --region "$REGION" \
  --stack-name "$STACK_02_NAME"

echo "Stack '$STACK_02_NAME' removido com sucesso."

# ---------------------------------------------------------------------------
# Passo 2: Remover o pacote ZIP do bucket Landing Zone
# (não é recurso do CloudFormation — foi enviado pelo deploy_lambda.sh)
# ---------------------------------------------------------------------------
echo ""
echo "Removendo pacote ZIP do bucket Landing Zone..."

# Verifica se o Stack 01 ainda existe para obter o nome do bucket
LANDING_BUCKET=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_01_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='LandingZoneBucketName'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [[ -z "$LANDING_BUCKET" ]]; then
  echo "Aviso: Stack '$STACK_01_NAME' não encontrado ou sem outputs."
  echo "O arquivo s3://.../$S3_KEY pode precisar ser removido manualmente."
else
  S3_URI="s3://$LANDING_BUCKET/$S3_KEY"

  # Verifica se o objeto existe antes de tentar remover
  if aws s3 ls "$S3_URI" --region "$REGION" > /dev/null 2>&1; then
    aws s3 rm "$S3_URI" --region "$REGION"
    echo "Arquivo $S3_URI removido."
  else
    echo "Arquivo $S3_URI não encontrado (já removido ou nunca enviado)."
  fi
fi

echo ""
echo "Remoção concluída."
