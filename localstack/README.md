# Testes Locais com LocalStack

Esta pasta contém os artefatos utilizados para **testar a Lambda de ingestão da Landing Zone localmente**, sem gerar custos no AWS Academy Learner Lab.

O ambiente simula os serviços da AWS (S3, Lambda e SSM Parameter Store) por meio do **LocalStack** em Docker, permitindo validar o download e particionamento dos dados do Kaggle (~12 GB) antes de qualquer deploy real.

> **Nota:** Esta configuração foi utilizada apenas durante a fase de desenvolvimento da ingestão de dados, sem grande desenvolvimentos nas demais etapas do projeto. Em produção, a Lambda é deployada diretamente no AWS Academy via CloudFormation (`infrastructure/`).

## Conteúdo da Pasta

| Arquivo | Descrição |
|---|---|
| `docker-compose.yaml` | Sobe o LocalStack e o container `aws-setup` que orquestra a criação dos recursos |
| `dockerfile` | Imagem do container `aws-setup`, baseada em `amazon/aws-cli` com Python e `requests` |
| `aws-setup.sh` | Script que cria o bucket S3, injeta as credenciais do Kaggle no SSM e faz o deploy da Lambda |
| `localstack.md` | Documentação detalhada do passo a passo original de execução |

## Pré-requisitos

- **Docker e Docker Compose** instalados
- **Credenciais do Kaggle** — conta com Token de API gerado (`kaggle.json`)

## Como Executar

### 1. Configurar as credenciais

Na pasta `infrastructure/`, copie `.env.example` para `.env` e preencha:

```env
# Credenciais reais do Kaggle
KAGGLE_USERNAME=seu_usuario_aqui
KAGGLE_KEY=sua_chave_secreta_aqui

# Credenciais fictícias para o LocalStack (não alterar)
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_SESSION_TOKEN=test
```

### 2. Subir o ambiente

Execute a partir desta pasta (`localstack/`):

```bash
docker-compose down -v
docker-compose up -d --build
```

### 3. Acompanhar o setup

```bash
docker logs -f aws_setup
```

Aguarde a mensagem `[SUCESSO] Setup da Landing Zone na AWS simulada concluído.`

### 4. Invocar a Lambda

```bash
docker exec -it localstack_main awslocal lambda invoke \
    --function-name landing-zone-ingestion \
    --payload '{}' \
    /tmp/resposta_landing.json
```

> O terminal ficará bloqueado por alguns minutos durante o processamento.

### 5. Validar os dados no S3 simulado

```bash
docker exec -it localstack_main awslocal s3 ls s3://eedb015-g05-landing/raw/health_insurance/ --recursive
```

### 6. Limpar o ambiente

```bash
docker-compose down -v
```

## Troubleshooting

**Erro `error getting credentials` no Windows/WSL:**

```bash
rm -f ~/.docker/config.json
docker logout
docker-compose up -d --build
```
