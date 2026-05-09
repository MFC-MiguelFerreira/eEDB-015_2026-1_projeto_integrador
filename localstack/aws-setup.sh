#!/bin/sh
set -e

echo "--- A aguardar que o LocalStack esteja totalmente operacional... ---"
until aws --endpoint-url=http://localstack:4566 s3 ls > /dev/null 2>&1; do
    echo "A aguardar...";
    sleep 2;
done
echo "--- LocalStack está pronto! A iniciar o deploy da Landing Zone... ---"

echo "Passo 1: A instalar dependências (zip, python3, pip)..."
yum install -y zip python3 python3-pip > /dev/null

echo "Passo 2: A criar bucket S3 (eedb015-g05-landing)..."
aws --endpoint-url=http://localstack:4566 s3 mb s3://eedb015-g05-landing || true

echo "Passo 3: A configurar credenciais do Kaggle no SSM Parameter Store local..."
# Valida se o .env carregou corretamente as variáveis antes de injetar
if [ -z "$KAGGLE_USERNAME" ] || [ -z "$KAGGLE_KEY" ]; then
    echo "ERRO: As variáveis KAGGLE_USERNAME e KAGGLE_KEY não estão definidas no ficheiro .env!"
    exit 1
fi

aws --endpoint-url=http://localstack:4566 ssm put-parameter \
    --name "/eedb015/kaggle/username" --value "$KAGGLE_USERNAME" --type "SecureString" --overwrite > /dev/null
aws --endpoint-url=http://localstack:4566 ssm put-parameter \
    --name "/eedb015/kaggle/key" --value "$KAGGLE_KEY" --type "SecureString" --overwrite > /dev/null
echo "Credenciais de $KAGGLE_USERNAME configuradas com sucesso no SSM."

echo "Passo 4: A empacotar a nova Lambda de Landing Zone..."
mkdir -p /tmp/landing_pkg

# O caminho correto direto para a pasta src:
echo "Passo 4: A empacotar a nova Lambda de Landing Zone..."
mkdir -p /tmp/landing_pkg

# O caminho correto (sem a pasta duplicada):
cp /aws/src/lambdas/landing_zone_ingestion/handler.py /tmp/landing_pkg/handler.py

pip3 install requests -t /tmp/landing_pkg/ > /dev/null
cd /tmp/landing_pkg
zip -r /aws/landing.zip . > /dev/null
cd /aws

echo "Passo 5: A fazer o deploy da função Lambda..."
# Cria a função com timeout de 15 minutos ou atualiza o código se ela já existir
aws --endpoint-url=http://localstack:4566 lambda create-function \
    --function-name landing-zone-ingestion \
    --runtime python3.11 \
    --handler handler.lambda_handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://landing.zip \
    --environment Variables="{LANDING_BUCKET=eedb015-g05-landing,AWS_ENDPOINT_URL=http://localstack:4566}" \
    --timeout 900 > /dev/null || aws --endpoint-url=http://localstack:4566 lambda update-function-code --function-name landing-zone-ingestion --zip-file fileb://landing.zip > /dev/null

echo "Passo 6: A aguardar pela ativação da Lambda..."
aws --endpoint-url=http://localstack:4566 lambda wait function-active-v2 --function-name landing-zone-ingestion

echo "[SUCESSO] Setup da Landing Zone na AWS simulada concluído."
exit 0