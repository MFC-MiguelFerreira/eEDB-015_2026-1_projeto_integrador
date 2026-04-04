#!/bin/bash
# Lê o arquivo .env e gera ~/.aws/credentials e ~/.aws/config
# no formato esperado pelo AWS CLI / boto3.

ENV_FILE="/home/hadoop/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[setup-aws] Aviso: $ENV_FILE não encontrado. Configure as credenciais manualmente."
  exit 0
fi

# Carrega as variáveis do .env (ignora linhas de comentário e linhas vazias)
while IFS='=' read -r key value; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  export "$key=$value"
done < "$ENV_FILE"

mkdir -p /home/hadoop/.aws

cat > /home/hadoop/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
EOF

cat > /home/hadoop/.aws/config <<EOF
[default]
region = ${AWS_DEFAULT_REGION:-us-east-1}
output = json
EOF

chmod 600 /home/hadoop/.aws/credentials
chmod 600 /home/hadoop/.aws/config

echo "[setup-aws] ~/.aws/credentials e ~/.aws/config criados com sucesso."
