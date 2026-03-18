#!/usr/bin/env bash
# =============================================================================
# deploy_lambda.sh — Empacota e implanta a Lambda de ingestão na Landing Zone
#
# Uso:
#   ./infrastructure/scripts/deploy_lambda.sh
#
# Pré-requisitos:
#   1. Stack 01 (storage) já implantado via deploy.sh 01-storage
#   2. Python 3 instalado localmente (para instalar dependências no pacote)
#   3. Credenciais AWS configuradas em infrastructure/.env
#
# O que este script faz:
#   1. Carrega credenciais do .env
#   2. Obtém o nome do bucket Landing Zone nos Outputs do Stack 01
#   3. Cria o pacote ZIP com o código da Lambda e suas dependências
#   4. Faz upload do ZIP para s3://{landing-bucket}/lambdas/landing-zone-ingestion/
#   5. Implanta (ou atualiza) o Stack 02 via CloudFormation
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

STACK_01_NAME="eEDB015-01-storage"
STACK_02_NAME="eEDB015-02-lambda-ingestion"
TEMPLATE="$SCRIPT_DIR/../cloudformation/stacks/02-lambda-ingestion.yaml"
PARAMS_FILE="$SCRIPT_DIR/../cloudformation/parameters/dev.json"

LAMBDA_SOURCE_DIR="$PROJECT_ROOT/src/lambdas/landing_zone_ingestion"
S3_KEY="lambdas/landing-zone-ingestion/function.zip"
BUILD_DIR="/tmp/lambda_build_landing_zone_ingestion"
ZIP_PATH="/tmp/landing-zone-ingestion-function.zip"

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
if [[ ! -f "$TEMPLATE" ]]; then
  echo "Erro: template não encontrado em $TEMPLATE"
  exit 1
fi

if [[ ! -f "$LAMBDA_SOURCE_DIR/handler.py" ]]; then
  echo "Erro: handler.py não encontrado em $LAMBDA_SOURCE_DIR"
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
# Passo 2: Montar o pacote ZIP da Lambda
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Empacotando a Lambda..."
echo "===================================================================="

# Limpa build anterior
rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

# Instala dependências na pasta de build
if [[ -f "$LAMBDA_SOURCE_DIR/requirements.txt" ]]; then
  echo "Instalando dependências de requirements.txt..."
  pip install \
    --quiet \
    --requirement "$LAMBDA_SOURCE_DIR/requirements.txt" \
    --target "$BUILD_DIR"
fi

# Copia o código-fonte para a raiz do pacote
cp "$LAMBDA_SOURCE_DIR/handler.py" "$BUILD_DIR/handler.py"

# Cria o ZIP a partir da pasta de build
echo "Criando ZIP do pacote usando Python (compatível com Windows)..."
# Prefer python3, fallback to python
PYTHON_CMD="$(command -v python3 || command -v python || true)"
if [[ -z "$PYTHON_CMD" ]]; then
  echo "Erro: Python não encontrado. O empacotamento requer Python 3 ou Python instalados."
  exit 1
fi

"$PYTHON_CMD" - "$BUILD_DIR" "$ZIP_PATH" <<'PY'
import os
import sys
import zipfile
import fnmatch

build_dir = sys.argv[1]
zip_path = sys.argv[2]

excl_patterns = ('*.pyc',)

with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
  for root, dirs, files in os.walk(build_dir):
    # skip __pycache__ directories entirely
    if '__pycache__' in root:
      continue
    for fname in files:
      if any(fnmatch.fnmatch(fname, pat) for pat in excl_patterns):
        continue
      fullpath = os.path.join(root, fname)
      # arcname should be relative path inside the build dir
      arcname = os.path.relpath(fullpath, build_dir)
      zf.write(fullpath, arcname)
print('ZIP criado em: {}'.format(zip_path))
PY

echo "Pacote criado em: $ZIP_PATH"

# ---------------------------------------------------------------------------
# Passo 3: Upload do pacote para o bucket Landing Zone
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Enviando pacote para s3://$LANDING_BUCKET/$S3_KEY ..."
echo "===================================================================="

aws s3 cp "$ZIP_PATH" "s3://$LANDING_BUCKET/$S3_KEY" --region "$REGION"

echo "Upload concluído."

# ---------------------------------------------------------------------------
# Passo 4: Implantar (ou atualizar) o Stack 02
# ---------------------------------------------------------------------------
echo ""
echo "===================================================================="
echo " Stack   : $STACK_02_NAME"
echo " Template: $TEMPLATE"
echo " Params  : $PARAMS_FILE + LambdaCodeS3Bucket + LambdaCodeS3Key"
echo " Região  : $REGION"
echo "===================================================================="

# --parameter-overrides não aceita file:// misturado com Key=Value.
# Lê o JSON e converte cada entrada para o formato Key=Value esperado pela CLI.
PARAMS=()
while IFS= read -r param; do
  PARAMS+=("$param")
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE")
PARAMS+=("LambdaCodeS3Bucket=$LANDING_BUCKET")
PARAMS+=("LambdaCodeS3Key=$S3_KEY")

aws cloudformation deploy \
  --region "$REGION" \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK_02_NAME" \
  --parameter-overrides "${PARAMS[@]}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset

echo ""
echo "Stack '$STACK_02_NAME' implantado com sucesso."
echo ""

# Exibe os Outputs do stack
echo "---- Outputs -------------------------------------------------------"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --stack-name "$STACK_02_NAME" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table

# Limpa arquivos temporários
rm -rf "$BUILD_DIR" "$ZIP_PATH"
echo ""
echo "Arquivos temporários de build removidos."
