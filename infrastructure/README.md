# Infraestrutura — eEDB-015/2026-1

Infraestrutura como código (IaC) do projeto, provisionada via **AWS CloudFormation** no ambiente AWS Academy Learner Lab.

## Estrutura

```
infrastructure/
├── cloudformation/
│   ├── stacks/                   # Templates CloudFormation, numerados por ordem de deploy
│   │   ├── 01-storage.yaml
│   │   └── 02-lambda-ingestion.yaml
│   └── parameters/               # Valores de parâmetros por ambiente
│       └── dev.json
├── scripts/
│   ├── deploy.sh                 # Cria ou atualiza os stacks 01, 03, ...
│   ├── destroy.sh                # Remove os stacks 01, 03, ... (com confirmação)
│   ├── deploy_lambda.sh          # Empacota e implanta a Lambda de ingestão (Stack 02)
│   └── destroy_lambda.sh         # Remove a Lambda de ingestão e o pacote ZIP do S3
├── .env.example                  # Modelo de credenciais (versionado)
└── .env                          # Credenciais reais — NÃO commitado (.gitignore)
```

## Pré-requisitos

- AWS CLI instalado e configurado com as credenciais do Learner Lab
- Python 3 instalado localmente (necessário para empacotar a Lambda)
- As credenciais são **efêmeras** e mudam a cada nova sessão do Learner Lab

## Configurando as credenciais

Os scripts carregam automaticamente as credenciais de `infrastructure/.env`. Use o arquivo de exemplo como ponto de partida:

```bash
cp infrastructure/.env.example infrastructure/.env
# edite o .env com os valores da tela "AWS Details" do Learner Lab
```

O `.env` está no `.gitignore` e **nunca será commitado**. O `.env.example` é o modelo versionado para referência dos membros do grupo.

## Stacks disponíveis

| #   | Stack                    | Descrição                                                                                        | Script de deploy              |
| --- | ------------------------ | ------------------------------------------------------------------------------------------------ | ----------------------------- |
| 01  | `01-storage`             | Buckets S3 das camadas Landing, Bronze, Silver, Gold + Athena                                    | `deploy.sh 01-storage`        |
| 02  | `02-lambda-ingestion`    | Função Lambda que baixa os CSVs do Kaggle e salva na Landing Zone + CloudWatch Log Group         | `deploy_lambda.sh`            |

### Stack 02 — Lambda de Ingestão

**Recursos criados:**

| Recurso                        | Tipo                        | Detalhes                                                                                         |
| ------------------------------ | --------------------------- | ------------------------------------------------------------------------------------------------ |
| `LandingZoneIngestionFunction` | `AWS::Lambda::Function`     | Runtime Python 3.12 · Timeout 15 min · Memória 512 MB · /tmp 10 240 MB · Role `LabRole`         |
| `LandingZoneIngestionLogGroup` | `AWS::Logs::LogGroup`       | Retenção de 7 dias · `DeletionPolicy: Delete`                                                    |

**Variáveis de ambiente da Lambda:**

| Variável        | Origem                                      | Descrição                                    |
| --------------- | ------------------------------------------- | -------------------------------------------- |
| `LANDING_BUCKET`| `ImportValue` do Stack 01                   | Nome do bucket Landing Zone                  |
| `LOG_LEVEL`     | Fixo (`INFO`)                               | Nível de log para o CloudWatch               |

**Outputs exportados (para stacks futuros, ex: Step Functions):**

| Export                                        | Valor                        |
| --------------------------------------------- | ---------------------------- |
| `eedb015-g05-landing-ingestion-function-name` | Nome da função Lambda        |
| `eedb015-g05-landing-ingestion-function-arn`  | ARN da função Lambda         |

## Como fazer deploy

### Stack 01 — Storage

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy.sh 01-storage
```

O script executa `aws cloudformation deploy`, que cria o stack se não existir ou aplica apenas as mudanças (changeset) se já existir. Ao final, exibe os Outputs com os nomes e ARNs dos recursos criados.

### Stack 02 — Lambda de Ingestão

O Stack 02 tem um processo de deploy próprio pois inclui empacotamento do código Python:

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy_lambda.sh
```

O script automaticamente:
1. Busca o nome do bucket Landing Zone nos Outputs do Stack 01
2. Instala as dependências do `requirements.txt` e empacota o código em um ZIP
3. Faz upload do ZIP para `s3://{landing-bucket}/lambdas/landing-zone-ingestion/function.zip`
4. Implanta (ou atualiza) o Stack 02 via CloudFormation

> **Pré-requisito:** o Stack 01 (`01-storage`) deve estar implantado antes do Stack 02.

## Como remover um stack

### Stack 01 — Storage

```bash
./infrastructure/scripts/destroy.sh 01-storage
```

> **Atenção:** os buckets de dados (Landing, Bronze, Silver, Gold) têm `DeletionPolicy: Retain` e **não são deletados** junto com o stack — isso protege os dados de uma remoção acidental. Para deletar os buckets, esvazie-os manualmente no console S3 antes.

### Stack 02 — Lambda de Ingestão

```bash
./infrastructure/scripts/destroy_lambda.sh
```

O script remove o Stack 02 (Lambda + CloudWatch Log Group) e também apaga o pacote ZIP do bucket Landing Zone (que não é um recurso CloudFormation e precisa de limpeza explícita).

> **Ordem recomendada para remoção completa:** destruir o Stack 02 antes do Stack 01.

.