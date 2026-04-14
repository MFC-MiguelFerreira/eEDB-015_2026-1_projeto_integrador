# Infraestrutura — eEDB-015/2026-1

Infraestrutura como código (IaC) do projeto, provisionada via **AWS CloudFormation** no ambiente AWS Academy Learner Lab.

## Estrutura

```
infrastructure/
├── cloudformation/
│   ├── stacks/                   # Templates CloudFormation, numerados por ordem de deploy
│   │   ├── 01-storage.yaml
│   │   ├── 02-lambda-ingestion.yaml
│   │   ├── 03-glue-catalog.yaml
│   │   ├── 04-glue-etl.yaml
│   │   └── 05-step-functions.yaml
│   └── parameters/               # Valores de parâmetros por ambiente
│       └── dev.json
├── scripts/
│   ├── deploy.sh                 # Cria ou atualiza os stacks 01, 03, ...
│   ├── destroy.sh                # Remove os stacks 01, 03, ... (com confirmação)
│   ├── deploy_lambda.sh          # Empacota e implanta a Lambda de ingestão (Stack 02)
│   ├── destroy_lambda.sh         # Remove a Lambda de ingestão e o pacote ZIP do S3
│   ├── deploy_glue_jobs.sh       # Faz upload dos scripts Glue para S3 e implanta o Stack 04
│   └── deploy_step_functions.sh  # Implanta a orquestração Step Functions (Stack 05)
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

| #   | Stack                    | Descrição                                                                                        | Script de deploy                |
| --- | ------------------------ | ------------------------------------------------------------------------------------------------ | ------------------------------- |
| 01  | `01-storage`             | Buckets S3 das camadas Landing, Bronze, Silver, Gold + Athena Results                            | `deploy.sh 01-storage`          |
| 02  | `02-lambda-ingestion`    | Função Lambda que baixa os CSVs do Kaggle e salva na Landing Zone + CloudWatch Log Group         | `deploy_lambda.sh`              |
| 03  | `03-glue-catalog`        | Glue Databases (Bronze, Silver, Gold) + Athena Workgroup apontando para os buckets do Stack 01   | `deploy.sh 03-glue-catalog`     |
| 04  | `04-glue-etl`            | Glue Jobs 5.0: Landing → Bronze e Bronze → Silver                                                 | `deploy_glue_jobs.sh`           |
| 05  | `05-step-functions`      | Step Functions Standard: orquestra Lambda de ingestão → Glue Landing→Bronze → Glue Bronze→Silver | `deploy_step_functions.sh`      |

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

### Stack 03 — Glue Data Catalog

**Recursos criados:**

| Recurso                | Tipo                        | Detalhes                                                                                              |
| ---------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------- |
| `GlueDatabaseBronze`   | `AWS::Glue::Database`       | Database `eedb015_bronze` · `LocationUri` aponta para o bucket Bronze do Stack 01                    |
| `GlueDatabaseSilver`   | `AWS::Glue::Database`       | Database `eedb015_silver` · `LocationUri` aponta para o bucket Silver do Stack 01                    |
| `GlueDatabaseGold`     | `AWS::Glue::Database`       | Database `eedb015_gold` · `LocationUri` aponta para o bucket Gold do Stack 01                        |
| `AthenaWorkgroup`      | `AWS::Athena::WorkGroup`    | Workgroup `eedb015-g05` · resultados no bucket athena-results · limite de 1 GB de scan por query     |

**Outputs exportados (para stacks de ETL: Glue Jobs, Step Functions):**

| Export                                   | Valor                             |
| ---------------------------------------- | --------------------------------- |
| `eedb015-g05-bronze-database-name`       | Nome do Glue Database Bronze      |
| `eedb015-g05-silver-database-name`       | Nome do Glue Database Silver      |
| `eedb015-g05-gold-database-name`         | Nome do Glue Database Gold        |
| `eedb015-g05-athena-workgroup-name`      | Nome do Athena Workgroup          |

> **Dependência:** o Stack 03 importa os nomes dos buckets do Stack 01 via `!ImportValue`. O CloudFormation impede que o Stack 01 seja destruído enquanto o Stack 03 existir.

### Stack 04 — Glue Jobs Landing → Bronze e Bronze → Silver

**Recursos criados:**

| Recurso                    | Tipo                     | Detalhes                                                                                                      |
| -------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `GlueJobLandingToBronze`   | `AWS::Glue::Job`         | Glue 5.0 · Spark 3.5.2 · Python 3.11 · Iceberg 1.6.1 · G.1X × 2 workers · Timeout 120 min · Role `LabRole` |
| `GlueJobBronzeToSilver`    | `AWS::Glue::Job`         | Glue 5.0 · Spark 3.5.2 · Python 3.11 · Iceberg 1.6.1 · G.1X × 2 workers · Timeout 120 min · Role `LabRole` |
| `GlueJobLandingToBronzeLogGroup` | `AWS::Logs::LogGroup` | `/aws-glue/jobs/eedb015-landing-to-bronze` · Retenção de 7 dias                                              |
| `GlueJobBronzeToSilverLogGroup`  | `AWS::Logs::LogGroup` | `/aws-glue/jobs/eedb015-bronze-to-silver` · Retenção de 7 dias                                               |

**Comportamento do job (`src/glue_jobs/landing_to_bronze.py`):**

- Descobre todos os CSVs em `s3://{landing}/raw/health_insurance/YYYY/NomeArquivo.csv`
- Cria **uma tabela por tipo de arquivo** no database Bronze (ex: `rate`, `plan_attributes`, `service_area`)
- Dados não são modificados: todos os campos lidos como `string` (`inferSchema=false`)
- Adiciona coluna `year` (int) extraída do caminho — partição de cada tabela Iceberg
- Idempotente: re-executar sobrescreve apenas as partições processadas (`.overwritePartitions()`)

**Comportamento do job (`src/glue_jobs/bronze_to_silver.py`):**

- Descobre automaticamente as tabelas do database Bronze no Glue Catalog
- Ignora tabelas com prefixo `raw_`
- Converte colunas string para tipos `double`, `boolean`, `timestamp` e `integer`
- Aplica regras de limpeza como `No Charge → 0.0` e `Not Applicable → null`
- Recria as tabelas correspondentes no database Silver

**Parâmetro opcional `--YEAR`:** reprocessa apenas um ano sem tocar os demais.

**Outputs exportados (para stack de orquestração: Step Functions):**

| Export                                         | Valor                             |
| ---------------------------------------------- | --------------------------------- |
| `eedb015-g05-landing-to-bronze-job-name`       | Nome do Glue Job                  |
| `eedb015-g05-bronze-to-silver-job-name`        | Nome do Glue Job                  |

> **Dependências:** os Stacks 01 e 03 devem estar implantados antes do Stack 04.

### Stack 05 — Step Functions (Pipeline Health Insurance)

**Recursos criados:**

| Recurso                      | Tipo                                   | Detalhes                                                                                              |
| ---------------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `HealthInsurancePipeline`    | `AWS::StepFunctions::StateMachine`     | Standard Workflow · Role `LabRole` · Logging nível ERROR · definição embutida no template             |
| `StateMachineLogGroup`       | `AWS::Logs::LogGroup`                  | `/aws/states/eedb015-g05-health-insurance-pipeline` · Retenção de 7 dias                             |

**Fluxo da máquina de estados:**

```
InvokeLandingIngestion  →  CheckIngestionResult  →  StartLandingToBronze  →  StartBronzeToSilver  →  PipelineSucceeded
   (Lambda)               (Choice State)           (Glue Job .sync)          (Glue Job .sync)
              │                            │                           │
            statusCode 500                    falha                       falha
              ↓                            ↓                           ↓
           IngestionFailed                 BronzeFailed                SilverFailed
```

**Estados e integrações:**

| Estado                    | Tipo     | Integração                               | Timeout   |
| ------------------------- | -------- | ---------------------------------------- | --------- |
| `InvokeLandingIngestion`  | Task     | `lambda:invoke` (síncrono)               | 16 min    |
| `CheckIngestionResult`    | Choice   | Verifica `statusCode` (200/207 → avança) | —         |
| `StartLandingToBronze`    | Task     | `glue:startJobRun.sync:2` (polling auto) | 130 min   |
| `StartBronzeToSilver`     | Task     | `glue:startJobRun.sync:2` (polling auto) | 130 min   |
| `PipelineSucceeded`       | Succeed  | —                                        | —         |
| `IngestionFailed`         | Fail     | —                                        | —         |
| `BronzeFailed`            | Fail     | —                                        | —         |
| `SilverFailed`            | Fail     | —                                        | —         |

**Outputs exportados:**

| Export                                              | Valor                              |
| --------------------------------------------------- | ---------------------------------- |
| `eedb015-g05-pipeline-state-machine-name`           | Nome da State Machine              |
| `eedb015-g05-pipeline-state-machine-arn`            | ARN da State Machine               |

> **Dependências:** os Stacks 02 e 04 devem estar implantados antes do Stack 05 (o script valida isso automaticamente).

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

### Stack 03 — Glue Data Catalog

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy.sh 03-glue-catalog
```

> **Pré-requisito:** o Stack 01 (`01-storage`) deve estar implantado antes do Stack 03, pois ele importa os nomes dos buckets via `!ImportValue`.

### Stack 04 — Glue Jobs de ETL

O Stack 04 tem um processo de deploy próprio pois inclui upload do script PySpark para o S3:

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy_glue_jobs.sh
```

O script automaticamente:
1. Busca o nome do bucket Landing Zone nos Outputs do Stack 01
2. Faz upload de todos os scripts `src/glue_jobs/*.py` para `s3://{landing-bucket}/glue-scripts/`
3. Implanta (ou atualiza) o Stack 04 via CloudFormation

> **Pré-requisitos:** os Stacks 01 e 03 devem estar implantados antes do Stack 04.

Para executar o job após o deploy:

```bash
# Processa todos os anos disponíveis na Landing Zone
aws glue start-job-run --job-name eedb015-landing-to-bronze

# Reprocessa apenas um ano específico (idempotente)
aws glue start-job-run \
  --job-name eedb015-landing-to-bronze \
  --arguments '{"--YEAR": "2015"}'
```

### Stack 05 — Step Functions

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy_step_functions.sh
```

O script automaticamente:
1. Verifica se os Stacks 02 e 04 estão com status `CREATE_COMPLETE` ou `UPDATE_COMPLETE`
2. Implanta (ou atualiza) o Stack 05 via CloudFormation
3. Exibe o ARN da máquina de estados com o comando pronto para iniciar uma execução

> **Pré-requisitos:** os Stacks 02 (`deploy_lambda.sh`) e 04 (`deploy_glue_jobs.sh`) devem estar implantados antes do Stack 05.

Para iniciar o pipeline após o deploy:

```bash
# Executa o pipeline completo (todos os arquivos da Landing Zone)
aws stepfunctions start-execution \
  --state-machine-arn <ARN exibido pelo deploy_step_functions.sh> \
  --input '{}'

# Executa o pipeline filtrando arquivos específicos para a Lambda
aws stepfunctions start-execution \
  --state-machine-arn <ARN exibido pelo deploy_step_functions.sh> \
  --input '{"files": ["2014/Rate.csv", "2014/PlanAttributes.csv"]}'
```

## Como remover um stack

### Stack 01 — Storage

```bash
./infrastructure/scripts/destroy.sh 01-storage
```

> **Atenção:** todos os buckets (Landing, Bronze, Silver, Gold, Athena Results) têm `DeletionPolicy: Delete` e **serão deletados** junto com o stack. Os buckets precisam estar **vazios** para que o CloudFormation consiga removê-los — esvazie-os manualmente no console S3 antes de executar o destroy.

### Stack 02 — Lambda de Ingestão

```bash
./infrastructure/scripts/destroy_lambda.sh
```

O script remove o Stack 02 (Lambda + CloudWatch Log Group) e também apaga o pacote ZIP do bucket Landing Zone (que não é um recurso CloudFormation e precisa de limpeza explícita).

### Stack 03 — Glue Data Catalog

```bash
./infrastructure/scripts/destroy.sh 03-glue-catalog
```

Remove os três Glue Databases e o Athena Workgroup. As tabelas catalogadas dentro dos databases também são removidas, mas **os dados nos buckets S3 não são afetados**.

> **Ordem recomendada para remoção completa:** destruir o Stack 04, depois o Stack 03, e por último o Stack 01 (o CloudFormation bloqueia a remoção de stacks enquanto existirem `!ImportValue` ativos apontando para eles).

### Stack 04 — Glue Job Landing → Bronze

```bash
./infrastructure/scripts/destroy.sh 04-glue-etl
```

Remove o Glue Job e o CloudWatch Log Group. Os scripts `.py` em `s3://{landing-bucket}/glue-scripts/` **não são removidos** (não são recursos CloudFormation) — apague-os manualmente se necessário.

### Stack 05 — Step Functions

```bash
./infrastructure/scripts/destroy.sh 05-step-functions
```

Remove a State Machine e o CloudWatch Log Group. Não há recursos externos para limpar manualmente.

> **Ordem recomendada para remoção completa:** 05 → 04 → 03 → 02 → 01 (o CloudFormation bloqueia a remoção de stacks enquanto existirem `!ImportValue` ativos apontando para eles).
