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
│   │   ├── 04-glue-bronze.yaml
│   │   ├── 05-glue-silver.yaml
│   │   ├── 06-step-functions.yaml
│   │   └── 07-glue-gold.yaml
│   └── parameters/               # Valores de parâmetros por ambiente
│       └── dev.json
├── scripts/
│   ├── deploy.sh                 # Cria ou atualiza os stacks 01, 03, ...
│   ├── destroy.sh                # Remove os stacks 01, 03, ... (com confirmação)
│   ├── deploy_lambda.sh          # Empacota e implanta a Lambda de ingestão (Stack 02)
│   ├── destroy_lambda.sh         # Remove a Lambda de ingestão e o pacote ZIP do S3
│   ├── deploy_glue_jobs.sh       # Upload dos scripts Glue/SQLs para S3 e implanta os Stacks 04, 05 e 07
│   └── deploy_step_functions.sh  # Implanta a orquestração Step Functions (Stack 06)
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

| #   | Stack                    | Descrição                                                                                              | Script de deploy                |
| --- | ------------------------ | ------------------------------------------------------------------------------------------------------ | ------------------------------- |
| 01  | `01-storage`             | Buckets S3 das camadas Landing, Bronze, Silver, Gold + Athena Results                                  | `deploy.sh 01-storage`          |
| 02  | `02-lambda-ingestion`    | Função Lambda que baixa os CSVs do Kaggle e salva na Landing Zone + CloudWatch Log Group               | `deploy_lambda.sh`              |
| 03  | `03-glue-catalog`        | Glue Databases (Bronze, Silver, Gold) + Athena Workgroup apontando para os buckets do Stack 01         | `deploy.sh 03-glue-catalog`     |
| 04  | `04-glue-bronze`         | Glue Job 5.0: Landing Zone → Bronze                                                                    | `deploy_glue_jobs.sh`           |
| 05  | `05-glue-silver`         | Glue Job 5.0: Bronze → Silver                                                                          | `deploy_glue_jobs.sh`           |
| 06  | `06-step-functions`      | Step Functions Standard: orquestra Lambda → Bronze → Silver → Gold                                    | `deploy_step_functions.sh`      |
| 07  | `07-glue-gold`           | Glue Job Python Shell: Silver → Gold via Athena (DELETE + INSERT nas tabelas Iceberg)                  | `deploy_glue_jobs.sh`           |

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

**Outputs exportados:**

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

**Outputs exportados:**

| Export                                   | Valor                             |
| ---------------------------------------- | --------------------------------- |
| `eedb015-g05-bronze-database-name`       | Nome do Glue Database Bronze      |
| `eedb015-g05-silver-database-name`       | Nome do Glue Database Silver      |
| `eedb015-g05-gold-database-name`         | Nome do Glue Database Gold        |
| `eedb015-g05-athena-workgroup-name`      | Nome do Athena Workgroup          |

> **Dependência:** o Stack 03 importa os nomes dos buckets do Stack 01 via `!ImportValue`. O CloudFormation impede que o Stack 01 seja destruído enquanto o Stack 03 existir.

### Stack 04 — Glue Job Landing Zone → Bronze

**Recursos criados:**

| Recurso                          | Tipo                     | Detalhes                                                                                                      |
| -------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `GlueJobLandingToBronze`         | `AWS::Glue::Job`         | Glue 5.0 · Spark 3.5 · Python 3.11 · Iceberg · G.1X × 2 workers · Timeout 120 min · Role `LabRole`          |
| `GlueJobLogGroup`                | `AWS::Logs::LogGroup`    | `/aws-glue/jobs/eedb015-landing-to-bronze` · Retenção de 7 dias                                              |

**Comportamento do job (`src/glue_jobs/landing_to_bronze.py`):**

- Descobre todos os CSVs em `s3://{landing}/raw/health_insurance/YYYY/NomeArquivo.csv`
- Cria **uma tabela por tipo de arquivo** no database Bronze (ex: `rate`, `plan_attributes`, `service_area`)
- Dados não são modificados: todos os campos lidos como `string` (`inferSchema=false`)
- Adiciona coluna `year` (int) extraída do caminho — partição de cada tabela Iceberg
- Idempotente: re-executar sobrescreve apenas as partições processadas (`.overwritePartitions()`)

**Outputs exportados:**

| Export                                         | Valor                             |
| ---------------------------------------------- | --------------------------------- |
| `eedb015-g05-landing-to-bronze-job-name`       | Nome do Glue Job                  |

> **Dependências:** os Stacks 01 e 03 devem estar implantados antes do Stack 04.

### Stack 05 — Glue Job Bronze → Silver

**Recursos criados:**

| Recurso                          | Tipo                     | Detalhes                                                                                                      |
| -------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `GlueJobBronzeToSilver`          | `AWS::Glue::Job`         | Glue 5.0 · Spark 3.5 · Python 3.11 · Iceberg · G.1X × 2 workers · Timeout 120 min · Role `LabRole`          |
| `GlueJobBronzeToSilverLogGroup`  | `AWS::Logs::LogGroup`    | `/aws-glue/jobs/eedb015-bronze-to-silver` · Retenção de 7 dias                                               |

**Comportamento do job (`src/glue_jobs/bronze_to_silver.py`):**

- Descobre automaticamente as tabelas do database Bronze no Glue Catalog
- Converte colunas string para tipos `double`, `boolean`, `timestamp` e `integer`
- Aplica regras de limpeza como `No Charge → 0.0` e `Not Applicable → null`
- Recria as tabelas correspondentes no database Silver

**Outputs exportados:**

| Export                                         | Valor                             |
| ---------------------------------------------- | --------------------------------- |
| `eedb015-g05-bronze-to-silver-job-name`        | Nome do Glue Job                  |

> **Dependências:** os Stacks 01, 03 e 04 devem estar implantados antes do Stack 05.

### Stack 07 — Glue Job Silver → Gold

**Recursos criados:**

| Recurso                          | Tipo                     | Detalhes                                                                                                          |
| -------------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `GlueJobSilverToGold`            | `AWS::Glue::Job`         | Glue 3.0 · Python Shell · Python 3.9 · 1/16 DPU (0.0625) · Timeout 60 min · Role `LabRole`                      |
| `GlueJobSilverToGoldLogGroup`    | `AWS::Logs::LogGroup`    | `/aws-glue/jobs/eedb015-silver-to-gold` · Retenção de 7 dias                                                     |

**Comportamento do job (`src/glue_jobs/silver_to_gold.py`):**

- Job **Python Shell** (sem Spark): usa `boto3` para executar queries via Athena
- Lê os SQLs de inserção do S3 (`glue-scripts/sql/gold/*.sql`)
- Para cada tabela da camada Gold executa: `DELETE FROM <tabela>` → `INSERT SELECT` da Silver
- Respeita a ordem de dependência do modelo estrela: dimensões primeiro, depois fatos
- Tabelas populadas: `dim_time`, `dim_geography`, `dim_issuer`, `dim_benefit_category`, `dim_network`, `dim_plan`, `fct_market_competition`, `fct_plan_premium`, `fct_benefit_coverage`

**Parâmetros do job:**

| Parâmetro              | Origem                                           | Descrição                                      |
| ---------------------- | ------------------------------------------------ | ---------------------------------------------- |
| `--SQL_BUCKET`         | `GlueJobScriptsBucket` (parâmetro do stack)      | Bucket onde os SQLs foram carregados            |
| `--SQL_PREFIX`         | Fixo (`glue-scripts/sql/gold`)                   | Prefixo S3 com os arquivos `.sql`               |
| `--ATHENA_OUTPUT_BUCKET` | `ImportValue` do Stack 01                      | Bucket para resultados Athena                   |
| `--GOLD_DATABASE`      | `ImportValue` do Stack 03                        | Nome do Glue Database Gold                      |

**Outputs exportados:**

| Export                                         | Valor                             |
| ---------------------------------------------- | --------------------------------- |
| `eedb015-g05-silver-to-gold-job-name`          | Nome do Glue Job                  |

> **Dependências:** os Stacks 01, 03 e 05 devem estar implantados antes do Stack 07.

### Stack 06 — Step Functions (Pipeline Health Insurance)

**Recursos criados:**

| Recurso                      | Tipo                                   | Detalhes                                                                                              |
| ---------------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `HealthInsurancePipeline`    | `AWS::StepFunctions::StateMachine`     | Standard Workflow · Role `LabRole` · Logging nível ERROR · definição embutida no template             |
| `StateMachineLogGroup`       | `AWS::Logs::LogGroup`                  | `/aws/states/eedb015-g05-health-insurance-pipeline` · Retenção de 7 dias                             |

**Fluxo da máquina de estados:**

```
InvokeLandingIngestion  →  CheckIngestionResult  →  StartLandingToBronze  →  StartBronzeToSilver  →  StartSilverToGold  →  PipelineSucceeded
   (Lambda)               (Choice State)           (Glue Job .sync)          (Glue Job .sync)         (Glue Job .sync)
              │                            │                           │                        │
            statusCode 500             falha                         falha                    falha
              ↓                            ↓                           ↓                        ↓
           IngestionFailed             BronzeFailed                SilverFailed             GoldFailed
```

**Estados e integrações:**

| Estado                    | Tipo     | Integração                               | Timeout   |
| ------------------------- | -------- | ---------------------------------------- | --------- |
| `InvokeLandingIngestion`  | Task     | `lambda:invoke` (síncrono)               | 16 min    |
| `CheckIngestionResult`    | Choice   | Verifica `statusCode` (200/207 → avança) | —         |
| `StartLandingToBronze`    | Task     | `glue:startJobRun.sync` (polling auto)   | 130 min   |
| `StartBronzeToSilver`     | Task     | `glue:startJobRun.sync` (polling auto)   | 130 min   |
| `StartSilverToGold`       | Task     | `glue:startJobRun.sync` (polling auto)   | 70 min    |
| `PipelineSucceeded`       | Succeed  | —                                        | —         |
| `IngestionFailed`         | Fail     | —                                        | —         |
| `BronzeFailed`            | Fail     | —                                        | —         |
| `SilverFailed`            | Fail     | —                                        | —         |
| `GoldFailed`              | Fail     | —                                        | —         |

**Outputs exportados:**

| Export                                              | Valor                              |
| --------------------------------------------------- | ---------------------------------- |
| `eedb015-g05-pipeline-state-machine-name`           | Nome da State Machine              |
| `eedb015-g05-pipeline-state-machine-arn`            | ARN da State Machine               |

> **Dependências:** os Stacks 02, 04, 05 e 07 devem estar implantados antes do Stack 06 (o script valida isso automaticamente).

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

### Stacks 04, 05 e 07 — Glue Jobs (Bronze, Silver e Gold)

Os três Glue Jobs são implantados com um único script:

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy_glue_jobs.sh
```

O script automaticamente:
1. Busca o nome do bucket Landing Zone nos Outputs do Stack 01
2. Faz upload de todos os scripts `src/glue_jobs/*.py` para `s3://{landing-bucket}/glue-scripts/`
3. Faz upload dos SQLs de inserção Gold `src/.sql/insert/*.sql` para `s3://{landing-bucket}/glue-scripts/sql/gold/`
4. Implanta (ou atualiza) o Stack 04 (`04-glue-bronze`) via CloudFormation
5. Implanta (ou atualiza) o Stack 05 (`05-glue-silver`) via CloudFormation
6. Implanta (ou atualiza) o Stack 07 (`07-glue-gold`) via CloudFormation

> **Pré-requisitos:** os Stacks 01 e 03 devem estar implantados antes de executar este script.

Para executar os jobs individualmente após o deploy:

```bash
# Landing Zone → Bronze (todos os anos)
aws glue start-job-run --job-name eedb015-landing-to-bronze

# Bronze → Silver
aws glue start-job-run --job-name eedb015-bronze-to-silver

# Silver → Gold
aws glue start-job-run --job-name eedb015-silver-to-gold
```

### Stack 06 — Step Functions

```bash
# Da raiz do repositório:
./infrastructure/scripts/deploy_step_functions.sh
```

O script automaticamente:
1. Verifica se os Stacks 02, 04, 05 e 07 estão com status `CREATE_COMPLETE` ou `UPDATE_COMPLETE`
2. Implanta (ou atualiza) o Stack 06 via CloudFormation
3. Exibe o ARN da máquina de estados com o comando pronto para iniciar uma execução

> **Pré-requisitos:** os Stacks 02 (`deploy_lambda.sh`) e 04, 05, 07 (`deploy_glue_jobs.sh`) devem estar implantados antes do Stack 06.

Para iniciar o pipeline após o deploy:

```bash
# Executa o pipeline completo (Landing Zone → Bronze → Silver → Gold)
aws stepfunctions start-execution \
  --state-machine-arn <ARN exibido pelo deploy_step_functions.sh> \
  --input '{}'

# Executa o pipeline passando arquivos específicos para a Lambda de ingestão
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

### Stacks 04, 05 e 07 — Glue Jobs

```bash
./infrastructure/scripts/destroy.sh 04-glue-bronze
./infrastructure/scripts/destroy.sh 05-glue-silver
./infrastructure/scripts/destroy.sh 07-glue-gold
```

Remove cada Glue Job e seu CloudWatch Log Group. Os scripts `.py` e SQLs em `s3://{landing-bucket}/glue-scripts/` **não são removidos** (não são recursos CloudFormation) — apague-os manualmente se necessário.

### Stack 06 — Step Functions

```bash
./infrastructure/scripts/destroy.sh 06-step-functions
```

Remove a State Machine e o CloudWatch Log Group. Não há recursos externos para limpar manualmente.

> **Ordem recomendada para remoção completa:** 06 → 07 → 05 → 04 → 03 → 02 → 01 (o CloudFormation bloqueia a remoção de stacks enquanto existirem `!ImportValue` ativos apontando para eles).
