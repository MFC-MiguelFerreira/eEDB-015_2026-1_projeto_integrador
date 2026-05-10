# RUNBOOK — Projeto Integrador eEDB-015/2026-1

Procedimentos operacionais para configuração, execução e manutenção do pipeline de dados. Para a visão geral do projeto, consulte o [README.md](README.md).

---

## 1. Pré-requisitos de Ambiente

| Ferramenta | Versão mínima | Uso |
|---|---|---|
| AWS CLI | v2 | Deploy de stacks e execução de jobs |
| Docker Desktop / Engine | 24+ | Dev Container local |
| VS Code | 1.85+ | IDE com suporte a Dev Containers |
| Extensão Dev Containers | qualquer | Abrir o container no VS Code |
| Python | 3.10+ | Empacotamento da Lambda (script de deploy) |
| Conta Kaggle | — | Token de API para download do dataset |
| AWS Academy Learner Lab | — | Ambiente AWS com `LabRole` pré-configurada |

> As credenciais do Learner Lab são **efêmeras** (~4 horas). É necessário renová-las a cada nova sessão.

---

## 2. Configuração Inicial (primeira vez)

### 2.1 Clonar o repositório

```bash
git clone https://github.com/MFC-MiguelFerreira/eEDB-015_2026-1_projeto_integrador.git
cd eEDB-015_2026-1_projeto_integrador
```

### 2.2 Configurar credenciais

```bash
cp infrastructure/.env.example infrastructure/.env
```

Edite `infrastructure/.env` com os valores da tela **AWS Details → AWS CLI** do Learner Lab e com o token da API do Kaggle:

```dotenv
# AWS Academy (renovar a cada sessão)
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=ASIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...

# Kaggle API (estável entre sessões)
KAGGLE_USERNAME=...
KAGGLE_KEY=...
```

> O arquivo `.env` está no `.gitignore` e nunca será commitado. Use `.env.example` como referência versionada.

### 2.3 Verificar conectividade AWS

```bash
source infrastructure/.env && \
  aws sts get-caller-identity
```

A resposta deve exibir o ARN da `LabRole`. Se retornar erro, as credenciais estão expiradas — repita o passo 2.2.

---

## 3. Deploy da Infraestrutura AWS

Os recursos são provisionados via CloudFormation em 7 stacks numerados. Execute os scripts na ordem abaixo, **sempre da raiz do repositório**.

> Detalhes de cada stack (recursos criados, outputs exportados) estão em [infrastructure/README.md](infrastructure/README.md).

### 3.1 Stack 01 — Storage (S3)

```bash
./infrastructure/scripts/deploy.sh 01-storage
```

Cria os buckets S3 para Landing, Bronze, Silver, Gold e resultados do Athena.

### 3.2 Stack 03 — Glue Data Catalog

```bash
./infrastructure/scripts/deploy.sh 03-glue-catalog
```

Cria os Glue Databases (`eedb015_bronze`, `eedb015_silver`, `eedb015_gold`) e o Athena Workgroup.

> **Dependência:** Stack 01 deve estar ativo (importa nomes de buckets via `!ImportValue`).

### 3.3 Stack 02 — Lambda de Ingestão

```bash
./infrastructure/scripts/deploy_lambda.sh
```

Empacota o código Python, faz upload para S3 e provisiona a Lambda de download do Kaggle.

> **Dependência:** Stack 01.

### 3.4 Stacks 04, 05 e 07 — Glue Jobs

```bash
./infrastructure/scripts/deploy_glue_jobs.sh
```

Faz upload dos scripts `src/glue_jobs/*.py` e dos SQLs `src/.sql/insert/*.sql` para S3, depois provisiona os três Glue Jobs.

> **Dependência:** Stacks 01 e 03.

### 3.5 Stack 06 — Step Functions (orquestração)

```bash
./infrastructure/scripts/deploy_step_functions.sh
```

Provisiona a State Machine que encadeia Lambda → Bronze → Silver → Gold. O script valida automaticamente se os stacks dependentes estão ativos antes de prosseguir.

> **Dependência:** Stacks 02, 04, 05 e 07.

---

## 4. Execução do Pipeline

### 4.1 Pipeline completo (recomendado)

Execute via Step Functions para garantir a ordem e o tratamento de falhas:

```bash
aws stepfunctions start-execution \
  --state-machine-arn <ARN exibido pelo deploy_step_functions.sh> \
  --input '{}'
```

O pipeline executa em sequência:
1. Lambda de Ingestão → download dos CSVs do Kaggle para a Landing Zone
2. Glue Job `landing-to-bronze` → CSVs → tabelas Iceberg Bronze
3. Glue Job `bronze-to-silver` → tipagem, limpeza, tabelas Iceberg Silver
4. Glue Job `silver-to-gold` → esquema estrela via queries Athena

Tempo estimado: **~60–90 minutos** para o dataset completo (2014–2016).

### 4.2 Execução de jobs individuais

Para reprocessar apenas uma camada específica:

```bash
# Landing Zone → Bronze
aws glue start-job-run --job-name eedb015-landing-to-bronze

# Bronze → Silver
aws glue start-job-run --job-name eedb015-bronze-to-silver

# Silver → Gold
aws glue start-job-run --job-name eedb015-silver-to-gold
```

### 4.3 Acompanhar execução

```bash
# Status da última execução de um job
aws glue get-job-runs --job-name eedb015-silver-to-gold \
  --query 'JobRuns[0].{Status:JobRunState,Started:StartedOn,Duration:ExecutionTime}' \
  --output table

# Logs em tempo real (CloudWatch)
aws logs tail /aws-glue/jobs/eedb015-silver-to-gold --follow
```

### 4.4 Exportar dados para o dashboard

Após a Gold estar populada, execute o notebook de exportação dentro do Dev Container:

```
scripts/export_gold_to_csv.ipynb
```

Os CSVs são gravados em `data/exports/` e consumidos pelo `docs/index.html`.

---

## 5. Ambiente de Desenvolvimento Local (Dev Container)

O Dev Container replica o runtime do AWS Glue 5 (PySpark + `awsglue` + Iceberg) localmente, sem custo de créditos.

> Detalhes completos em [.devcontainer/README.md](.devcontainer/README.md).

### 5.1 Abrir o ambiente

1. Abra o VS Code na raiz do projeto.
2. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**.
3. Aguarde o build da imagem (primeira vez: ~5 min).

### 5.2 Renovar credenciais dentro do container

A cada nova sessão do Learner Lab:

1. Atualize o `infrastructure/.env` com as novas credenciais.
2. `Ctrl+Shift+P` → **Tasks: Run Task** → **Refresh AWS Credentials**.

### 5.3 Executar notebooks

Abra qualquer notebook em `scripts/`, selecione o kernel **Python 3.11.14** e execute as células sequencialmente.

> Selecionar outro kernel causará erros de importação do `awsglue`.

---

## 6. Validação e Testes

### 6.1 Verificar contagem de registros nas camadas

Execute via Athena (console AWS ou AWS CLI):

```sql
-- Bronze: verificar se os CSVs foram ingeridos
SELECT COUNT(*) FROM eedb015_bronze.rate WHERE year = 2016;

-- Silver: verificar tipagem aplicada
SELECT COUNT(*) FROM eedb015_silver.plan_attributes WHERE businessyear = 2016;

-- Gold: verificar se o esquema estrela foi populado
SELECT 'dim_time'             AS tabela, COUNT(*) AS linhas FROM eedb015_gold.dim_time
UNION ALL
SELECT 'dim_plan',             COUNT(*) FROM eedb015_gold.dim_plan
UNION ALL
SELECT 'fct_plan_premium',     COUNT(*) FROM eedb015_gold.fct_plan_premium
UNION ALL
SELECT 'fct_benefit_coverage', COUNT(*) FROM eedb015_gold.fct_benefit_coverage
UNION ALL
SELECT 'fct_market_competition', COUNT(*) FROM eedb015_gold.fct_market_competition;
```

Contagens esperadas na Gold (dataset completo 2014–2016):

| Tabela | Ordem de grandeza |
|---|---|
| `dim_time` | 3 linhas |
| `dim_geography` | ~50 linhas |
| `dim_plan` | ~30.000–50.000 |
| `fct_plan_premium` | ~2–5 milhões |
| `fct_benefit_coverage` | ~1–3 milhões |
| `fct_market_competition` | ~150 linhas |

### 6.2 Validar integridade referencial (FK check)

```sql
-- Planos na fct_plan_premium sem correspondência em dim_plan (deve retornar 0)
SELECT COUNT(*) AS orphans
FROM eedb015_gold.fct_plan_premium f
LEFT JOIN eedb015_gold.dim_plan d ON f.plan_sk = d.plan_sk
WHERE d.plan_sk IS NULL;
```

### 6.3 Smoke test das queries analíticas

Execute uma query por questão para confirmar que a Gold responde às perguntas de negócio:

```bash
# Q2 — Competição vs. Prêmio (resultado deve ter linhas por estado/ano)
aws athena start-query-execution \
  --query-string "$(cat src/.sql/analytics/q2/competicao_vs_premio_por_estado.sql)" \
  --work-group eedb015-g05 \
  --result-configuration OutputLocation=s3://<athena-results-bucket>/
```

---

## 7. Reprocessamento e Atualização

### 7.1 Reprocessar a camada Gold

O job Silver → Gold é **idempotente**: executa `DELETE FROM` antes de cada `INSERT`, então pode ser reexecutado livremente:

```bash
aws glue start-job-run --job-name eedb015-silver-to-gold
```

### 7.2 Reprocessar a Silver

A Silver também é idempotente (sobrescreve partições). Para reprocessar um ano específico, passe como argumento:

```bash
aws glue start-job-run \
  --job-name eedb015-bronze-to-silver \
  --arguments '{"--YEAR_FILTER": "2016"}'
```

### 7.3 Atualizar scripts Glue

Após editar um script em `src/glue_jobs/`, faça upload e reinicie o job:

```bash
./infrastructure/scripts/deploy_glue_jobs.sh   # faz upload dos .py e .sql para S3
aws glue start-job-run --job-name eedb015-silver-to-gold
```

### 7.4 Renovar credenciais AWS (recorrente)

A cada nova sessão do Learner Lab (~4 horas):

```bash
# 1. Edite infrastructure/.env com as novas credenciais
# 2. Exporte para o shell atual:
export $(grep -v '^#' infrastructure/.env | xargs)
# 3. Confirme:
aws sts get-caller-identity
```

---

## 8. Remoção dos Recursos

Para remover toda a infraestrutura e evitar consumo de créditos:

```bash
# Ordem obrigatória (inversa das dependências)
./infrastructure/scripts/destroy.sh 06-step-functions
./infrastructure/scripts/destroy.sh 07-glue-gold
./infrastructure/scripts/destroy.sh 05-glue-silver
./infrastructure/scripts/destroy.sh 04-glue-bronze
./infrastructure/scripts/destroy.sh 03-glue-catalog
./infrastructure/scripts/destroy_lambda.sh
./infrastructure/scripts/destroy.sh 01-storage   # esvaziar os buckets S3 antes!
```

> Os buckets S3 precisam estar **vazios** antes de remover o Stack 01. Esvazie-os pelo console AWS ou via `aws s3 rm s3://<bucket> --recursive`.

---

## 9. Problemas Conhecidos e Contingências

| Problema | Causa provável | Ação |
|---|---|---|
| `ExpiredTokenException` em qualquer comando AWS | Credenciais do Learner Lab expiradas | Renovar `infrastructure/.env` e exportar as variáveis (seção 7.4) |
| Job Glue falha com `EntityNotFoundException` | Tabela não existe na camada anterior | Verificar se o job da camada anterior concluiu com sucesso |
| Job Silver → Gold falha com timeout do Athena | Query pesada sem partição de ano | O job retenta automaticamente; se persistir, reduzir o escopo via `--YEAR_FILTER` |
| `import awsglue` falha no notebook | Kernel errado selecionado | Selecionar o kernel **Python 3.11.14** no notebook |
| Step Functions reporta `IngestionFailed` | Lambda não conseguiu baixar do Kaggle | Verificar `KAGGLE_USERNAME` e `KAGGLE_KEY` no `.env`; confirmar se o SSM Parameter Store tem os valores |
| Contagem Gold menor que o esperado | Filtro de planos dentários ou CSR removeu registros | Consultar `src/.sql/gold_layer.md` — filtros intencionais são documentados lá |
| GitHub Pages não atualiza o dashboard | Cache do browser ou deploy pendente | Forçar refresh (`Ctrl+Shift+R`) ou aguardar até 10 min após push na branch `main` |

### Limitações conhecidas

- **Athena não enforça FK constraints**: a integridade referencial é garantida pelo pipeline ETL. Um `plan_sk` órfão só ocorreria se um plano existisse na tabela `rate` mas não em `plan_attributes` — prevenido pelo JOIN obrigatório nos INSERTs.
- **Créditos AWS Academy**: o pipeline completo consome ~$2–5 por execução. Prefira jobs individuais para testes parciais.
- **Dados de 2017+ não estão no dataset**: as análises cobrem apenas 2014–2016.
- **`approx_percentile` na Gold**: a mediana em `fct_market_competition` tem ~1% de erro relativo (limitação do Athena sem `MEDIAN()` nativo).
