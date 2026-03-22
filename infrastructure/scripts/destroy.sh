#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Remove um stack CloudFormation e seus recursos
#
# Todos os buckets S3 usam DeletionPolicy=Delete, portanto serão deletados
# junto com o stack. Certifique-se de que os buckets estão vazios antes de
# executar — o S3 não permite deletar buckets com objetos via CloudFormation.
#
# Uso:
#   ./infrastructure/scripts/destroy.sh <stack>
#
# Exemplo:
#   ./infrastructure/scripts/destroy.sh 01-storage
# =============================================================================

set -euo pipefail

# Carrega credenciais do .env (se existir)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
  echo "Credenciais carregadas de $ENV_FILE"
fi

REGION="${AWS_DEFAULT_REGION:-us-east-1}"

STACK_FILE="${1:-}"
STACK_NAME="eEDB015-${STACK_FILE}"

if [[ -z "$STACK_FILE" ]]; then
  echo "Erro: informe o nome do stack."
  echo "Uso: $0 <stack>"
  echo "Exemplo: $0 01-storage"
  exit 1
fi

echo "===================================================================="
echo " ATENÇÃO: esta ação é irreversível."
echo " Stack a remover: $STACK_NAME"
echo " Região         : $REGION"
echo ""
echo " Todos os buckets S3 (Landing, Bronze, Silver, Gold, Athena)"
echo " SERÃO DELETADOS junto com o stack (DeletionPolicy=Delete)."
echo " Os buckets precisam estar vazios para que a deleção funcione."
echo "===================================================================="
echo ""
read -r -p "Confirma a remoção? (digite 'sim' para continuar): " CONFIRM

if [[ "$CONFIRM" != "sim" ]]; then
  echo "Operação cancelada."
  exit 0
fi

echo ""
echo "Removendo stack '$STACK_NAME'..."

aws cloudformation delete-stack \
  --region "$REGION" \
  --stack-name "$STACK_NAME"

echo "Aguardando remoção completa..."

aws cloudformation wait stack-delete-complete \
  --region "$REGION" \
  --stack-name "$STACK_NAME"

echo ""
echo "Stack '$STACK_NAME' removido com sucesso."
