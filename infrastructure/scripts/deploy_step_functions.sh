#!/usr/bin/env bash
# =============================================================================
# deploy_step_functions.sh — Implanta o stack 05 (Step Functions)
#
# Uso:
#   ./infrastructure/scripts/deploy_step_functions.sh [parametros]
#
# Exemplos:
#   ./infrastructure/scripts/deploy_step_functions.sh          # usa dev.json
#   ./infrastructure/scripts/deploy_step_functions.sh dev
#
# Pré-requisitos:
#   1. Stack 02 (02-lambda-ingestion) implantado via deploy_lambda.sh
#   2. Stack 04 (04-glue-bronze) implantado via deploy_glue_jobs.sh
#   3. Credenciais AWS configuradas em infrastructure/.env
#
# O que este script faz:
#   1. Carrega credenciais do .env
#   2. Implanta (ou atualiza) o Stack 05 via CloudFormation
#      — A definição da máquina de estados está embutida no template YAML
#        e é resolvida pelo CloudFormation via !ImportValue dos stacks 02 e 04.
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
PARAMS_ENV="${1:-dev}"

STACK_05_NAME="eEDB015-05-step-functions"
TEMPLATE="$SCRIPT_DIR/../cloudformation/stacks/05-step-functions.yaml"
PARAMS_FILE="$SCRIPT_DIR/../cloudformation/parameters/${PARAMS_ENV}.json"

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

# Verifica se os stacks dependentes existem antes de tentar o deploy
for DEPENDENCY in "eEDB015-02-lambda-ingestion" "eEDB015-04-glue-bronze"; do
  STATUS=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$DEPENDENCY" \
    --query "Stacks[0].StackStatus" \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [[ "$STATUS" != "CREATE_COMPLETE" && "$STATUS" != "UPDATE_COMPLETE" ]]; then
    echo "Erro: stack dependente '$DEPENDENCY' não está disponível (status: $STATUS)."
    echo "Execute os deploys na ordem correta antes de prosseguir:"
    echo "  1. ./infrastructure/scripts/deploy_lambda.sh"
    echo "  2. ./infrastructure/scripts/deploy_glue_jobs.sh"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Implantar (ou atualizar) o Stack 05
# ---------------------------------------------------------------------------
echo "===================================================================="
echo " Stack   : $STACK_05_NAME"
echo " Template: $TEMPLATE"
echo " Params  : $PARAMS_FILE"
echo " Região  : $REGION"
echo "===================================================================="

# Lê o JSON de parâmetros e converte para o formato Key=Value esperado pela CLI.
PARAMS=()
while IFS= read -r param; do
  PARAMS+=("$param")
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE")

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_05_NAME" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_05_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack
echo "---- Outputs -------------------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_05_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table

# Exibe o ARN da máquina de estados para execução rápida
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_05_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='StateMachineArn'].OutputValue" \
  --output text)

echo ""
echo "Para iniciar uma execução do pipeline:"
echo ""
echo "  aws stepfunctions start-execution \\"
echo "    --state-machine-arn $STATE_MACHINE_ARN \\"
echo "    --input '{}'"
echo ""
echo "Para iniciar uma execução passando arquivos específicos para a Lambda:"
echo ""
echo "  aws stepfunctions start-execution \\"
echo "    --state-machine-arn $STATE_MACHINE_ARN \\"
echo "    --input '{\"files\": [\"2014/Rate.csv\", \"2014/PlanAttributes.csv\"]}'"
