#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Provisiona (ou atualiza) um stack CloudFormation
#
# Uso:
#   ./infrastructure/scripts/deploy.sh <stack> [parametros]
#
# Exemplos:
#   ./infrastructure/scripts/deploy.sh 01-storage
#   ./infrastructure/scripts/deploy.sh 01-storage dev
#
# O script usa as credenciais já configuradas no ambiente (variáveis de
# ambiente do AWS Learner Lab: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_SESSION_TOKEN). Não é necessário passar --profile.
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
STACKS_DIR="$(dirname "$0")/../cloudformation/stacks"
PARAMS_DIR="$(dirname "$0")/../cloudformation/parameters"

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
STACK_FILE="${1:-}"
PARAMS_ENV="${2:-dev}"

if [[ -z "$STACK_FILE" ]]; then
  echo "Erro: informe o nome do stack (sem extensão)."
  echo "Uso: $0 <stack> [parametros]"
  echo "Exemplo: $0 01-storage"
  exit 1
fi

TEMPLATE="$STACKS_DIR/${STACK_FILE}.yaml"
PARAMS_FILE="$PARAMS_DIR/${PARAMS_ENV}.json"
STACK_NAME="eEDB015-${STACK_FILE}"

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
if [[ ! -f "$TEMPLATE" ]]; then
  echo "Erro: template não encontrado em $TEMPLATE"
  exit 1
fi

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Erro: arquivo de parâmetros não encontrado em $PARAMS_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
echo "===================================================================="
echo " Stack   : $STACK_NAME"
echo " Template: $TEMPLATE"
echo " Params  : $PARAMS_FILE"
echo " Região  : $REGION"
echo "===================================================================="

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides "file://$PARAMS_FILE" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack
echo "---- Outputs -------------------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table
