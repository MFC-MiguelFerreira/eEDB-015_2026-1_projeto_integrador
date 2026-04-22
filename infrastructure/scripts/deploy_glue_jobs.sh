#!/usr/bin/env bash
# =============================================================================
# deploy_glue_jobs.sh — Faz upload dos scripts Glue para S3 e implanta os
#                        stacks 04 (Glue Job Landing → Bronze),
#                        05 (Glue Job Bronze → Silver) e
#                        07 (Glue Job Silver → Gold)
#
# Uso:
#   ./infrastructure/scripts/deploy_glue_jobs.sh [parametros]
#
# Exemplos:
#   ./infrastructure/scripts/deploy_glue_jobs.sh          # usa dev.json
#   ./infrastructure/scripts/deploy_glue_jobs.sh dev
#
# Pré-requisitos:
#   1. Stack 01 (01-storage) implantado via deploy.sh 01-storage
#   2. Stack 03 (03-glue-catalog) implantado via deploy.sh 03-glue-catalog
#   3. Credenciais AWS configuradas em infrastructure/.env
#
# O que este script faz:
#   1. Carrega credenciais do .env
#   2. Obtém o nome do bucket Landing Zone nos Outputs do Stack 01
#   3. Faz upload de todos os scripts em src/glue_jobs/ para
#      s3://{landing-bucket}/glue-scripts/
#   4. Faz upload dos SQLs de inserção Gold em src/.sql/insert/ para
#      s3://{landing-bucket}/glue-scripts/sql/gold/
#   5. Implanta (ou atualiza) o Stack 04 via CloudFormation (Landing → Bronze)
#   6. Implanta (ou atualiza) o Stack 05 via CloudFormation (Bronze → Silver)
#   7. Implanta (ou atualiza) o Stack 07 via CloudFormation (Silver → Gold)
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
PARAMS_ENV="${1:-dev}"

STACK_01_NAME="eEDB015-01-storage"
STACK_04_NAME="eEDB015-04-glue-bronze"
STACK_05_NAME="eEDB015-05-glue-silver"
STACK_07_NAME="eEDB015-07-glue-gold"
TEMPLATE_04="$SCRIPT_DIR/../cloudformation/stacks/04-glue-bronze.yaml"
TEMPLATE_05="$SCRIPT_DIR/../cloudformation/stacks/05-glue-silver.yaml"
TEMPLATE_07="$SCRIPT_DIR/../cloudformation/stacks/07-glue-gold.yaml"
PARAMS_FILE="$SCRIPT_DIR/../cloudformation/parameters/${PARAMS_ENV}.json"
GLUE_SCRIPTS_DIR="$PROJECT_ROOT/src/glue_jobs"
SQL_INSERT_DIR="$PROJECT_ROOT/src/.sql/insert"
S3_SCRIPTS_PREFIX="glue-scripts"
S3_SQL_GOLD_PREFIX="glue-scripts/sql/gold"

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
if [[ ! -f "$TEMPLATE_04" ]]; then
  echo "Erro: template não encontrado em $TEMPLATE_04"
  exit 1
fi

if [[ ! -f "$TEMPLATE_05" ]]; then
  echo "Erro: template não encontrado em $TEMPLATE_05"
  exit 1
fi

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Erro: arquivo de parâmetros não encontrado em $PARAMS_FILE"
  exit 1
fi

if [[ ! -d "$GLUE_SCRIPTS_DIR" ]]; then
  echo "Erro: diretório de scripts Glue não encontrado em $GLUE_SCRIPTS_DIR"
  exit 1
fi

if [[ ! -d "$SQL_INSERT_DIR" ]]; then
  echo "Erro: diretório de SQLs Gold não encontrado em $SQL_INSERT_DIR"
  exit 1
fi

if [[ ! -f "$TEMPLATE_07" ]]; then
  echo "Erro: template não encontrado em $TEMPLATE_07"
  exit 1
fi

# ---------------------------------------------------------------------------
# Passo 1: Obter o nome do bucket Landing Zone (Output do Stack 01)
# ---------------------------------------------------------------------------
echo "===================================================================="
echo " Buscando bucket Landing Zone no Stack '$STACK_01_NAME'..."
echo "===================================================================="

LANDING_BUCKET=$(aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_01_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='LandingZoneBucketName'].OutputValue" \
  --output text)

if [[ -z "$LANDING_BUCKET" ]]; then
  echo "Erro: não foi possível obter o nome do bucket Landing Zone."
  echo "Verifique se o Stack '$STACK_01_NAME' está implantado e com status CREATE_COMPLETE."
  exit 1
fi

echo "Bucket Landing Zone: $LANDING_BUCKET"

# ---------------------------------------------------------------------------
# Passo 2: Upload dos scripts Glue para o bucket Landing Zone
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Enviando scripts Glue para s3://$LANDING_BUCKET/$S3_SCRIPTS_PREFIX/"
echo "===================================================================="

SCRIPTS_FOUND=0
for script in "$GLUE_SCRIPTS_DIR"/*.py; do
  # Ignora se não houver nenhum .py (glob sem match retorna o padrão literal)
  [[ -f "$script" ]] || continue
  filename="$(basename "$script")"
  aws s3 cp "$script" "s3://$LANDING_BUCKET/$S3_SCRIPTS_PREFIX/$filename" --region "$REGION"
  echo "  Upload concluído: $filename"
  SCRIPTS_FOUND=$((SCRIPTS_FOUND + 1))
done

if [[ $SCRIPTS_FOUND -eq 0 ]]; then
  echo "Erro: nenhum script .py encontrado em $GLUE_SCRIPTS_DIR"
  exit 1
fi

echo "$SCRIPTS_FOUND script(s) enviado(s)."

# ---------------------------------------------------------------------------
# Passo 3: Upload dos SQLs de inserção Gold para o bucket Landing Zone
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Enviando SQLs Gold para s3://$LANDING_BUCKET/$S3_SQL_GOLD_PREFIX/"
echo "===================================================================="

SQL_FOUND=0
for sql_file in "$SQL_INSERT_DIR"/*.sql; do
  [[ -f "$sql_file" ]] || continue
  filename="$(basename "$sql_file")"
  aws s3 cp "$sql_file" "s3://$LANDING_BUCKET/$S3_SQL_GOLD_PREFIX/$filename" --region "$REGION"
  echo "  Upload concluído: $filename"
  SQL_FOUND=$((SQL_FOUND + 1))
done

if [[ $SQL_FOUND -eq 0 ]]; then
  echo "Erro: nenhum arquivo .sql encontrado em $SQL_INSERT_DIR"
  exit 1
fi

echo "$SQL_FOUND SQL(s) enviado(s)."

# ---------------------------------------------------------------------------
# Passo 5: Implantar (ou atualizar) o Stack 04 (Landing → Bronze)
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Stack   : $STACK_04_NAME"
echo " Template: $TEMPLATE_04"
echo " Params  : $PARAMS_FILE + GlueJobScriptsBucket"
echo " Região  : $REGION"
echo "===================================================================="

# Lê o JSON de parâmetros e converte para o formato Key=Value esperado pela CLI.
# Mesmo padrão usado no deploy_lambda.sh.
PARAMS=()
while IFS= read -r param; do
  PARAMS+=("$param")
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE")
PARAMS+=("GlueJobScriptsBucket=$LANDING_BUCKET")

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE_04" \
  --stack-name "$STACK_04_NAME" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_04_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack 04
echo "---- Outputs Stack 04 ----------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_04_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table

# ---------------------------------------------------------------------------
# Passo 6: Implantar (ou atualizar) o Stack 05 (Bronze → Silver)
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Stack   : $STACK_05_NAME"
echo " Template: $TEMPLATE_05"
echo " Params  : $PARAMS_FILE + GlueJobScriptsBucket"
echo " Região  : $REGION"
echo "===================================================================="

PARAMS=()
while IFS= read -r param; do
  PARAMS+=("$param")
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE")
PARAMS+=("GlueJobScriptsBucket=$LANDING_BUCKET")

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE_05" \
  --stack-name "$STACK_05_NAME" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_05_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack 05
echo "---- Outputs Stack 05 ----------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_05_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table

# ---------------------------------------------------------------------------
# Passo 7: Implantar (ou atualizar) o Stack 07 (Silver → Gold)
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Stack   : $STACK_07_NAME"
echo " Template: $TEMPLATE_07"
echo " Params  : $PARAMS_FILE + GlueJobScriptsBucket"
echo " Região  : $REGION"
echo "===================================================================="

PARAMS=()
while IFS= read -r param; do
  PARAMS+=("$param")
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE")
PARAMS+=("GlueJobScriptsBucket=$LANDING_BUCKET")

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE_07" \
  --stack-name "$STACK_07_NAME" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_07_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack 07
echo "---- Outputs Stack 07 ----------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_07_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table
