# Documento de Handover — Projeto Integrador eEDB-015/2026-1
### Health Insurance Marketplace — Pipeline de Dados & Análise (Grupo 05)

**Disciplina:** Projeto Integrador (eEDB-015/2026-1) — Curso de Especialização em Big Data, Escola Politécnica da USP  
**Data de Elaboração:** Maio de 2026  
**Equipe Cedente (Grupo 05):** Ingrid Silva · Lucas Pereira · Miguel Ferreira · Simone Pereira  

---

## Sumário

1. [Processo de Handover](#1-processo-de-handover)
2. [Processo de Desenvolvimento](#2-processo-de-desenvolvimento)
3. [Contexto do que foi Vivido](#3-contexto-do-que-foi-vivido)
4. [Lições Aprendidas](#4-lições-aprendidas)
5. [Problemas Conhecidos](#5-problemas-conhecidos)
6. [Troubleshoots Conhecidos](#6-troubleshoots-conhecidos)
7. [Melhorias e Trabalhos Futuros Propostos](#7-melhorias-e-trabalhos-futuros-propostos)

---

## 1. Processo de Handover

### 1.1 O Que Está Sendo Transferido

Esta entrega transfere a propriedade completa de um **pipeline de dados de ponta a ponta** construído sobre a AWS, que ingere, transforma e analisa os dados do Health Insurance Marketplace (mercado de seguros de saúde dos EUA, 2014–2016). Estão incluídos:

- Infraestrutura como código (IaC) via AWS CloudFormation (7 stacks)
- Scripts de ETL deployados no AWS Glue (PySpark + Python Shell)
- Função Lambda de ingestão de dados do Kaggle
- Orquestração via AWS Step Functions
- Modelo de dados em esquema estrela (camada Gold, Apache Iceberg)
- Queries analíticas SQL que respondem a 4 questões de negócio (Q1–Q4)
- Dashboard analítico interativo publicado via GitHub Pages
- Ambiente de desenvolvimento local replicando o runtime do AWS Glue (Dev Container Docker)
- Documentação técnica completa no repositório

### 1.2 Estado Atual do Projeto

O projeto está **concluído** em relação ao escopo definido para a disciplina. As quatro questões analíticas principais (Q1–Q4) foram respondidas e os resultados estão visíveis no dashboard em:

> **https://mfc-miguelferreira.github.io/eEDB-015_2026-1_projeto_integrador/**

O pipeline completo foi executado com sucesso sobre o dataset 2014–2016. Os dados Gold estão exportados em CSV em `data/exports/` e consumidos diretamente pelo dashboard estático (`docs/index.html`). A infraestrutura AWS **não está ativa** no momento desta entrega (recursos removidos para evitar consumo de créditos do Learner Lab), mas pode ser recriada integralmente seguindo o RUNBOOK.

### 1.3 Repositório de Código

Todo o material está versionado publicamente em:

> **https://github.com/MFC-MiguelFerreira/eEDB-015_2026-1_projeto_integrador**

O repositório contém:

```
.
├── docs/                   # Dashboard HTML (GitHub Pages)
├── infrastructure/         # Templates CloudFormation + scripts de deploy/destroy
├── src/                    # Artefatos de produção: Glue Jobs, Lambda, queries SQL
│   ├── glue_jobs/          # Scripts PySpark das 3 camadas ETL
│   ├── lambdas/            # Lambda de ingestão Kaggle → S3
│   └── .sql/               # DDL/DML Gold + queries analíticas Q1–Q4
├── scripts/                # Notebooks Jupyter de desenvolvimento local
├── data/exports/           # CSVs exportados da Gold para o dashboard
└── .devcontainer/          # Configuração do ambiente Docker local
```

Cada subpasta possui README próprio com detalhes operacionais. O ponto de entrada para operação é o **[RUNBOOK.md](RUNBOOK.md)**.

### 1.4 Acessos e Pré-requisitos para Continuidade

Para reativar e operar o projeto, a equipe sucessora precisará de:

| Recurso | Onde Obter | Observação |
|---|---|---|
| Conta AWS Academy Learner Lab | Novo lab provisionado pela instituição | Credenciais expiram a cada ~4 horas |
| Token Kaggle API | kaggle.com → Account → API → Create New Token | Estável, não expira |
| Docker Desktop ou Docker Engine | docker.com | Versão 24+ |
| VS Code + extensão Dev Containers | marketplace.visualstudio.com | Para ambiente local |
| AWS CLI v2 | aws.amazon.com/cli | Para deploy e operação |
| Python 3.10+ | python.org | Para empacotamento da Lambda |

> **Importante:** As credenciais AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) são efêmeras e específicas de cada conta do Learner Lab. O arquivo `infrastructure/.env` **nunca foi commitado** (está no `.gitignore`). Use `infrastructure/.env.example` como modelo.

### 1.5 Recriação do Ambiente AWS (passo a passo resumido)

A recriação completa segue a ordem abaixo. Para detalhes completos, consulte o [RUNBOOK.md](RUNBOOK.md) e o [infrastructure/README.md](infrastructure/README.md).

```bash
# 1. Clone o repositório
git clone https://github.com/MFC-MiguelFerreira/eEDB-015_2026-1_projeto_integrador.git
cd eEDB-015_2026-1_projeto_integrador

# 2. Configure as credenciais
cp infrastructure/.env.example infrastructure/.env
# Edite .env com dados do Learner Lab e do Kaggle

# 3. Verifique conectividade
source infrastructure/.env && aws sts get-caller-identity

# 4. Deploy dos stacks CloudFormation (nesta ordem)
./infrastructure/scripts/deploy.sh 01-storage        # Buckets S3
./infrastructure/scripts/deploy.sh 03-glue-catalog   # Catálogo Glue + Athena Workgroup
./infrastructure/scripts/deploy_lambda.sh             # Lambda de ingestão
./infrastructure/scripts/deploy_glue_jobs.sh          # Glue Jobs (Bronze, Silver, Gold)
./infrastructure/scripts/deploy_step_functions.sh     # Orquestração Step Functions

# 5. Execute o pipeline completo
aws stepfunctions start-execution \
  --state-machine-arn <ARN exibido pelo deploy_step_functions.sh> \
  --input '{}'

# 6. Aguarde ~60–90 min e exporte os dados para o dashboard
# (dentro do Dev Container) executar: scripts/export_gold_to_csv.ipynb
```

---

## 2. Processo de Desenvolvimento

### 2.1 Visão Geral do que foi Desenvolvido

O projeto construiu um **Data Lake em arquitetura Medallion** na AWS, com quatro camadas bem definidas:

```
Kaggle CSV → Landing Zone (S3)
                    ↓  [Lambda Python 3.12]
             Bronze (Raw CSVs → Iceberg)
                    ↓  [Glue Job PySpark]
             Silver (Parquet tipado + Crosswalk)
                    ↓  [Glue Job Python Shell + Athena]
              Gold (Esquema estrela — 3 fatos, 6 dimensões)
                    ↓
          Athena SQL → CSV → Dashboard HTML (GitHub Pages)
```

A camada Gold implementa um **esquema estrela** com:
- 3 tabelas de fato: `fct_plan_premium`, `fct_benefit_coverage`, `fct_market_competition`
- 6 dimensões: `dim_plan`, `dim_issuer`, `dim_network`, `dim_geography`, `dim_benefit_category`, `dim_time`

### 2.2 Principais Etapas Executadas

| Fase | Atividade | Artefatos Gerados |
|---|---|---|
| **1. Exploração** | Análise do dataset Kaggle, identificação de tabelas, anomalias e relações | `scripts/bronze_exploration.ipynb`, `scripts/silver_exploration.md` |
| **2. Infraestrutura** | Provisionamento IaC dos buckets S3, catálogo Glue e Athena | `infrastructure/cloudformation/stacks/01-storage.yaml`, `03-glue-catalog.yaml` |
| **3. Ingestão (Landing)** | Lambda que baixa os CSVs do Kaggle via API e os carrega no S3 | `src/lambdas/landing_zone_ingestion/handler.py` |
| **4. ETL Bronze** | Glue Job que lê os CSVs brutos e cria tabelas Iceberg particionadas por ano | `src/glue_jobs/landing_to_bronze.py` |
| **5. ETL Silver** | Glue Job que tipifica, limpa e aplica o Crosswalk de linhagem de planos | `src/glue_jobs/bronze_to_silver.py` |
| **6. Modelagem Gold** | Design do esquema estrela, documentação de filtros críticos (CSR, rate, age) | `src/.sql/gold_layer.md`, `src/.sql/gold_catalog.md` |
| **7. ETL Gold** | Glue Job Python Shell que executa DDL/DML via Athena | `src/glue_jobs/silver_to_gold.py`, `src/.sql/create/`, `src/.sql/insert/` |
| **8. Orquestração** | Step Functions encadeando Lambda → Bronze → Silver → Gold com tratamento de falhas | `infrastructure/cloudformation/stacks/06-step-functions.yaml` |
| **9. Análise** | Queries SQL respondendo Q1–Q4; exportação para CSV | `src/.sql/analytics/q1/` até `q4/`, `scripts/export_gold_to_csv.ipynb` |
| **10. Dashboard** | Dashboard HTML interativo com gráficos Plotly.js publicado via GitHub Pages | `docs/index.html` |

### 2.3 Ferramentas Utilizadas

| Categoria | Ferramenta/Serviço | Versão/Detalhe |
|---|---|---|
| Armazenamento | Amazon S3 + Apache Iceberg | Formato de tabela com time travel e idempotência |
| Ingestão | AWS Lambda | Python 3.12, timeout 15 min |
| ETL (pesado) | AWS Glue Jobs | Versão 5.0, Spark 3.5, Python 3.11 |
| ETL (leve) | AWS Glue Python Shell | Versão 3.0, Python 3.9, boto3 |
| Orquestração | AWS Step Functions | Standard Workflow |
| Catálogo | AWS Glue Data Catalog | Databases bronze/silver/gold |
| Consulta | Amazon Athena | Workgroup `eedb015-g05` |
| IaC | AWS CloudFormation | 7 stacks com dependências via `!ImportValue` |
| Dev local | Docker + Dev Container | Imagem `amazon/aws-glue-libs:5` |
| Dashboard | HTML + Plotly.js | Estático, sem backend |
| Publicação | GitHub Pages | Branch `main`, pasta `docs/` |
| Dataset | Kaggle API | Health Insurance Marketplace (HHS) |

### 2.4 Entregas Realizadas

- Pipeline ETL completo e funcional (Landing → Bronze → Silver → Gold)
- Infraestrutura como código reproducível (7 stacks CloudFormation)
- Modelo de dados documentado com catálogo de campos e justificativas de decisão
- Queries analíticas para Q1–Q4 organizadas e comentadas
- Dashboard analítico interativo com respostas visuais às quatro questões
- Ambiente local de desenvolvimento (Dev Container) replicando o runtime AWS Glue
- Documentação técnica completa (README, RUNBOOK, gold_layer.md, gold_catalog.md)
- Testes de validação via Athena (contagem de registros + FK check)

---

## 3. Contexto do que foi Vivido

### 3.1 Cenário do Projeto

O dataset do Health Insurance Marketplace (Kaggle) é volumoso e estruturalmente complexo. A tabela `rate` — principal fonte de dados de prêmio — possui **dezenas de milhões de linhas** (uma por combinação de plano × estado × idade × tabaco). O principal desafio técnico foi construir joins corretos entre as tabelas sem incorrer em explosões cartesianas que inviabilizariam qualquer processamento.

O ambiente AWS Academy impôs restrições adicionais: a `LabRole` (IAM Role obrigatória, não pode ser modificada), credenciais efêmeras que expiram a cada ~4 horas e créditos limitados que penalizavam execuções longas ou redundantes no Glue.

### 3.2 Principais Decisões Tomadas

**a) Filtro CSR obrigatório (`csrvariationtype LIKE 'Standard%'`)**
Planos Silver têm até 6 variantes por plano base no dataset. Sem o filtro, a contagem de planos inflaria 6×, e os copays de quimioterapia apareceriam artificialmente zerados (variantes CSR 87/94 reduzem cost-sharing para beneficiários de baixa renda). Este é o filtro mais crítico do pipeline — sua ausência invalida toda a análise Q1.

**b) Truncamento do `planid` para joins com `rate`**
A tabela `rate` usa IDs de 14 caracteres; `plan_attributes` usa 17 (com sufixo `-XX`). Sem `SUBSTR(pa.planid, 1, 14)`, o join produz zero registros — silenciosamente, sem erro — corrompendo as tabelas de fato inteiras.

**c) Glue Python Shell para a camada Gold**
A transformação Silver → Gold não precisava de Spark (os dados Silver já estavam limpos e o processamento era SQL via Athena). Usar Python Shell (0.0625 DPU) em vez de Spark (G.1X × 2 workers) reduziu o custo de execução em ~80%.

**d) Iceberg em vez de Hive Tables**
O Apache Iceberg garante idempotência dos INSERTs (possível reprocessar sem duplicar dados), partition pruning automático sem `MSCK REPAIR TABLE`, e time travel para rollback em caso de carga incorreta.

**e) Surrogate keys por composição natural**
Em vez de sequências auto-incrementadas (que o Athena não suporta), as surrogate keys são composições determinísticas dos campos naturais (ex: `plan_id_base || '_' || year`). Isso permite que as tabelas de fato calculem a FK sem precisar fazer lookup nas dimensões, simplificando a orquestração.

**f) Benchmark de idade 27 para `fct_market_competition`**
O CMS (Centers for Medicare & Medicaid Services) usa 27 anos como perfil de referência em todas as publicações oficiais do Marketplace. Adotamos esse padrão para garantir comparabilidade com literatura externa.

### 3.3 Dificuldades Enfrentadas

**Credenciais efêmeras do Learner Lab:** O maior atrito operacional do projeto. A cada nova sessão (~4 horas), era necessário renovar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` em `infrastructure/.env` e re-exportar para o shell — e para dentro do Dev Container separadamente. O processo de renovação foi documentado e automatizado via VS Code Task ("Refresh AWS Credentials").

**Volume da tabela `rate`:** Com dezenas de milhões de linhas por ano, qualquer query sem partition pruning esgotava o timeout do Athena (30 min). A solução foi garantir que todos os joins na Gold passassem primeiro pelo filtro `businessyear` e `state_code`.

**Inconsistência estrutural do dataset:** A descoberta do truncamento `planid` (14 vs 17 caracteres) foi feita durante testes de contagem — a fato de prêmios retornava zero registros sem nenhuma mensagem de erro. Este tipo de bug "silencioso" consumiu horas de debugging.

**Variantes CSR:** A existência de até 6 linhas por plano em `plan_attributes` foi identificada apenas durante a validação da contagem de planos — que estava 6× acima do esperado. A documentação oficial do CMS não torna essa multiplicidade óbvia; foi necessário inspecionar os dados para entender o padrão.

**Custo de execuções redundantes:** Jobs Glue Spark consomem créditos mesmo quando falham. Nos primeiros ciclos de desenvolvimento, falhas por bugs de configuração (ex: Role errada, bucket errado) consumiram créditos sem produzir resultado. O desenvolvimento em Dev Container local foi a solução — permite validar 90% da lógica ETL sem custo.

### 3.4 Mudanças Ocorridas Durante o Projeto

- O Glue Job Silver → Gold foi redesenhado de PySpark para Python Shell após identificar que a lógica era inteiramente SQL/Athena — redução significativa de custo e complexidade.
- O LocalStack (emulação local da AWS) foi explorado como alternativa mas descartado: a versão comunitária não suporta o Glue Data Catalog completo nem o Athena com Iceberg, tornando-o inadequado para testar o pipeline completo.
- A camada Gold passou por duas iterações de modelagem: a primeira tentativa incluía todas as variantes CSR, o que produziu resultados incorretos; a segunda (versão final) aplica o filtro `Standard%` consistentemente.

### 3.5 Pontos de Atenção

- O pipeline consome aproximadamente **$2–5 em créditos AWS** por execução completa. Prefira reprocessar camadas individuais quando possível.
- Os dados cobrem apenas **2014–2016**. Não há dados de 2017+ no dataset público do Kaggle.
- A mediana em `fct_market_competition` usa `approx_percentile` com erro relativo de ~1% (limitação do Athena sem `MEDIAN()` nativo).
- O Athena **não enforça FK constraints**: a integridade referencial é garantida pelos INSERTs do pipeline. Um JOIN mal construído na Silver pode gerar órfãos na Gold sem aviso.

---

## 4. Lições Aprendidas

### 4.1 Boas Práticas Adotadas

**Infraestrutura como código desde o início.** Os 7 stacks CloudFormation com dependências declaradas via `!ImportValue` permitiram que qualquer membro do grupo recriasse o ambiente completo em ~30 minutos sem intervenção manual. O retorno desse investimento inicial foi alto.

**Ambiente local que replica o runtime de produção.** O Dev Container com a imagem oficial `amazon/aws-glue-libs:5` eliminou a classe inteira de bugs "funciona local, falha no Glue". A disciplina de desenvolver e validar no Dev Container antes de deployar economizou créditos e tempo.

**Documentar o "porquê" dos filtros críticos.** O arquivo `src/.sql/gold_layer.md` explica cada decisão de modelagem com contexto técnico e de negócio. Sem ele, qualquer pessoa nova no código veria filtros aparentemente arbitrários e os removeria — destruindo a integridade das análises.

**Idempotência em todos os jobs.** A possibilidade de reexecutar qualquer job sem duplicar dados (via `INSERT OVERWRITE` no Iceberg ou `DELETE FROM` + `INSERT` na Gold) eliminou o medo de tentativas. Bugs foram corrigidos e os jobs reexecutados sem necessidade de limpeza manual.

**Notebooks como rascunho, scripts como produto.** A distinção clara entre `scripts/` (desenvolvimento, exploração) e `src/glue_jobs/` (produção) manteve o repositório organizado e evitou código experimental chegando ao pipeline de produção.

**Validação por contagem de registros.** Antes de cada camada ir para produção, as contagens de registros eram verificadas contra expectativas documentadas. Isso detectou o bug das variantes CSR (contagem 6× acima do esperado) antes que chegasse ao dashboard.

### 4.2 Erros Evitáveis

**Não testar o join `rate × plan_attributes` logo no início.** O truncamento de `planid` (14 vs 17 chars) deveria ter sido identificado durante a exploração do Bronze, não durante o desenvolvimento da Gold. Uma célula simples de `SELECT COUNT(*) FROM rate JOIN plan_attributes ON planid_rate = planid_attr` teria revelado o problema imediatamente.

**Confiar na documentação oficial sem inspecionar os dados.** A documentação do CMS descreve o dataset de forma que sugere uma linha por plano em `plan_attributes`. Os dados reais têm até 6 linhas por plano base. A inspeção direta dos dados (não apenas do dicionário de dados) deveria ser o primeiro passo.

**Não automatizar a renovação de credenciais desde o início.** A renovação manual de credenciais a cada 4 horas causou erros e interrupções desnecessárias. A automação via VS Code Task e o script `setup-aws-credentials.sh` foram implementados tarde — deveriam estar presentes desde a configuração inicial.

**Usar Glue Spark onde Python Shell seria suficiente.** A decisão inicial de usar Spark para o job Silver → Gold foi equivocada. A reformulação para Python Shell economizou créditos e reduziu o tempo de start-up do job de ~3 min para segundos.

### 4.3 Recomendações para a Equipe Sucessora

1. **Leia o `gold_layer.md` antes de tocar em qualquer SQL.** É o documento mais importante do repositório — explica cada filtro e cada decisão de join. Remover um filtro sem entender seu propósito corrompe os resultados silenciosamente.

2. **Sempre desenvolva no Dev Container.** Nunca edite `src/glue_jobs/*.py` e faça deploy direto sem testar no Dev Container primeiro. O custo de um job Glue com bug é real (créditos + tempo).

3. **Renove as credenciais antes de qualquer operação.** A primeira causa de falha de qualquer comando AWS é credencial expirada. Verifique com `aws sts get-caller-identity` antes de iniciar qualquer sessão de trabalho.

4. **Use o pipeline via Step Functions, não jobs avulsos.** O Step Functions garante a ordem correta de execução e captura falhas com estado rastreável. Jobs avulsos executados fora de ordem podem corromper camadas.

5. **Verifique contagens após cada execução.** As contagens esperadas estão documentadas no [RUNBOOK.md](RUNBOOK.md) (seção 6.1). Se uma tabela tiver zero registros ou um valor muito diferente do esperado, há um problema de pipeline — investigue antes de prosseguir para a próxima camada.

---

## 5. Problemas Conhecidos

| ID | Problema | Impacto | Status |
|---|---|---|---|
| P01 | `approx_percentile` na `fct_market_competition` tem erro relativo de ~1% | Mediana de prêmio com precisão limitada | Documentado, aceitável (Athena não tem `MEDIAN()`) |
| P02 | Dados de 2017+ não estão no dataset | Análises limitadas a 2014–2016 | Fora do escopo do dataset disponível |
| P03 | `network_plan_count` é proxy indireto de tamanho de rede | Análise Q4 é indireta — não mede número real de prestadores | Documentado em `gold_layer.md` (seção 10) |
| P04 | Athena não enforça FK constraints | Possibilidade de registros órfãos na Gold sem aviso | Prevenido pelos INSERTs com JOIN obrigatório |
| P05 | Créditos AWS se esgotam se o pipeline completo for executado muitas vezes | Risco de perda de acesso ao ambiente AWS antes do fim do lab | Mitigado pelo uso do Dev Container local |
| P06 | O LocalStack não suporta Glue Data Catalog + Athena + Iceberg na versão comunitária | Impossível testar o pipeline completo 100% local sem custo | Investigação descontinuada; Dev Container cobre 90% dos casos |
| P07 | GitHub Pages pode demorar até 10 min para refletir push em `main` | Dashboard pode parecer desatualizado após deploy | Aguardar propagação ou usar `Ctrl+Shift+R` |
| P08 | O campo `moop_individual` e `deductible_individual` em `dim_plan` podem ser nulos para planos sem MOOP declarado | Análises financeiras devem filtrar `IS NOT NULL` | Documentado em `gold_catalog.md` |

---

## 6. Troubleshoots Conhecidos

### TS01 — `ExpiredTokenException` em qualquer comando AWS

**Sintoma:** Qualquer `aws ...` retorna `ExpiredTokenException` ou `InvalidClientTokenId`.  
**Causa:** Credenciais do Learner Lab expiradas (TTL de ~4 horas).  
**Solução:**
```bash
# 1. No painel do Learner Lab: AWS Details → AWS CLI → copie os novos valores
# 2. Edite infrastructure/.env com os novos valores
# 3. No shell:
export $(grep -v '^#' infrastructure/.env | xargs)
# 4. Confirme:
aws sts get-caller-identity
# 5. Se estiver dentro do Dev Container, execute também a task "Refresh AWS Credentials"
```

---

### TS02 — Job Glue falha com `EntityNotFoundException`

**Sintoma:** Job Glue falha com mensagem `EntityNotFoundException: Table 'eedb015_silver.rate' does not exist`.  
**Causa:** O job está tentando ler uma tabela de uma camada anterior que ainda não foi criada.  
**Diagnóstico:**
```bash
# Verifique se os jobs das camadas anteriores concluíram com sucesso:
aws glue get-job-runs --job-name eedb015-landing-to-bronze \
  --query 'JobRuns[0].{Status:JobRunState,Error:ErrorMessage}'
```
**Solução:** Execute os jobs na ordem correta (via Step Functions) ou aguarde a conclusão de cada camada antes de iniciar a próxima.

---

### TS03 — `import awsglue` falha no notebook

**Sintoma:** Célula com `from awsglue.context import GlueContext` lança `ModuleNotFoundError`.  
**Causa:** Kernel incorreto selecionado no Jupyter.  
**Solução:** No canto superior direito do notebook, selecione o kernel **Python 3.11.14** (ambiente `vscode_pyspark`). Qualquer outro kernel não tem o `awsglue` instalado.

---

### TS04 — Step Functions reporta `IngestionFailed`

**Sintoma:** A máquina de estados para no estado `IngestionFailed` logo no início.  
**Causa:** A Lambda não conseguiu autenticar com a API do Kaggle ou baixar os arquivos.  
**Diagnóstico:**
```bash
# Verifique os logs da Lambda:
aws logs tail /aws/lambda/LandingZoneIngestionFunction --follow
# Verifique se os parâmetros Kaggle estão no SSM:
aws ssm get-parameter --name /eedb015/kaggle/username --with-decryption
aws ssm get-parameter --name /eedb015/kaggle/key --with-decryption
```
**Solução:** Se os parâmetros SSM estiverem ausentes ou incorretos, recrie-os:
```bash
aws ssm put-parameter --name /eedb015/kaggle/username \
  --value "SEU_USUARIO_KAGGLE" --type SecureString --overwrite
aws ssm put-parameter --name /eedb015/kaggle/key \
  --value "SUA_KEY_KAGGLE" --type SecureString --overwrite
```

---

### TS05 — Job Silver → Gold falha com timeout do Athena

**Sintoma:** Job `eedb015-silver-to-gold` falha após ~60 min; logs mostram que a query Athena não concluiu.  
**Causa:** Uma query de INSERT grande (ex: `fct_plan_premium` com milhões de linhas) excedeu o timeout do Athena sem partição de ano.  
**Solução:** Reexecute o job com `--YEAR_FILTER` para processar um ano por vez:
```bash
aws glue start-job-run \
  --job-name eedb015-silver-to-gold \
  --arguments '{"--YEAR_FILTER": "2016"}'
# Repita para 2015 e 2014
```

---

### TS06 — Contagem Gold zero após execução do Silver → Gold

**Sintoma:** Query `SELECT COUNT(*) FROM eedb015_gold.fct_plan_premium` retorna 0 após o job concluir com sucesso.  
**Causa mais comum:** O job rodou mas o filtro de join `planid` não produziu correspondências — tipicamente por inconsistência de formato (`14 chars` vs `17 chars`).  
**Diagnóstico:**
```sql
-- Verifique se existem planos na Silver com o formato correto:
SELECT DISTINCT LENGTH(planid) AS len_planid, COUNT(*) AS qtd
FROM eedb015_silver.plan_attributes
GROUP BY 1;
-- Esperado: len=17 com a maioria dos registros
```
Se `len_planid` retornar 14 na Silver, houve regressão no Bronze → Silver. Reprocesse o job Silver garantindo que o `SUBSTR` não esteja sendo aplicado prematuramente.

---

### TS07 — Deploy CloudFormation falha com `ValidationError: No export named ...`

**Sintoma:** `aws cloudformation deploy` para os stacks 03–07 falha com `No export named eedb015-g05-landing-bucket-name`.  
**Causa:** O Stack 01 (Storage) não está ativo — foi removido ou não foi deployado.  
**Solução:** Execute `./infrastructure/scripts/deploy.sh 01-storage` e aguarde status `CREATE_COMPLETE` antes de prosseguir.

---

### TS08 — Rebuild do Dev Container necessário

**Sintoma:** O container foi removido ou está com comportamento inesperado (dependências corrompidas, credenciais antigas gravadas).  
**Solução:**
```bash
# Remove o container (mantém a imagem — rebuild mais rápido)
docker rm eedb015_g05_aws_glue_pyspark_environment

# No VS Code: Ctrl+Shift+P → Dev Containers: Reopen in Container
# O container será recriado (~2-5 min, usando a imagem cacheada)
```

---

## 7. Melhorias e Trabalhos Futuros Propostos

### 7.1 Dados e Cobertura Analítica

**Incorporar dados de 2017 em diante**  
O dataset do Kaggle cobre apenas 2014–2016. O CMS publica dados mais recentes (até 2023) no portal data.healthcare.gov. A arquitetura atual suporta novos anos sem modificação estrutural — bastaria adicionar os arquivos CSVs anuais na Landing Zone e reexecutar o pipeline.

**Questão Q5 (extra) — Monopólios e desigualdade geográfica**  
A questão Q5 foi definida como objetivo extra e não foi respondida completamente. A `fct_market_competition` já tem o campo `competition_tier` que classifica estados como `monopoly`, `low`, `moderate` ou `high`. Falta construir uma análise de correlação entre o `competition_tier` e o `avg_premium_individual` por condado (a análise atual é por estado, não por condado/área de serviço).

**Granularidade geográfica na Gold**  
A dimensão `dim_geography` está no nível de estado. O dataset original da tabela `service_area` contém dados por condado. Aprofundar a análise para o nível de condado permitiria identificar "desertos de cobertura" com maior precisão.

**Análise de linhagem de planos (Crosswalk)**  
O campo `plan_lineage_id_2014/2015/2016` em `dim_plan` foi construído para rastrear a evolução de um mesmo produto entre anos. Nenhuma query analítica atual usa esses campos. Uma análise de série temporal de prêmio por plano individual (não por categoria) seria possível e revelaria inflação real por produto.

### 7.2 Arquitetura e Infraestrutura

**Agendamento automático do pipeline**  
Atualmente, o pipeline é executado manualmente via `aws stepfunctions start-execution`. Uma EventBridge Rule poderia disparar a State Machine automaticamente (ex: primeiro dia de cada mês) para datasets atualizados periodicamente.

**Particionamento adicional por estado**  
Os Glue Jobs Bronze e Silver particionam apenas por `year`. Adicionar particionamento por `state_code` reduziria significativamente o volume de dados scaneado por queries que filtram por estado — impacto direto no custo do Athena.

**Testes automatizados de qualidade de dados**  
Atualmente, a validação é manual via queries Athena no RUNBOOK. Integrar o AWS Glue Data Quality (dqDL) ou uma biblioteca como Great Expectations permitiria validação automática após cada execução, com alertas via CloudWatch.

**Versionamento de schema com Iceberg Schema Evolution**  
Se o dataset for atualizado com novas colunas (ex: dados de 2017 têm campos adicionais), o Iceberg suporta evolução de schema sem reprocessamento. Implementar e documentar esse fluxo protegeria o pipeline de quebras em futuras atualizações de dados.

**Migração para Glue 5 completo no job Silver → Gold**  
O job `silver-to-gold` usa Glue 3.0 (Python Shell) por questões de custo. O Glue 5.0 unificou os runtimes PySpark e Python Shell. Migrar para Glue 5.0 permitiria usar recursos mais recentes e reduz dívida de manutenção de versões diferentes.

### 7.3 Dashboard e Visualização

**Dashboard dinâmico com backend**  
O dashboard atual é um arquivo HTML estático que lê CSVs locais. Para escalabilidade e dados sempre atualizados, substituir por uma solução com backend (ex: Streamlit na AWS, Amazon QuickSight conectado diretamente ao Athena, ou Metabase) eliminaria a necessidade de exportar CSVs manualmente após cada execução do pipeline.

**Filtros interativos no dashboard**  
Os gráficos atuais têm interatividade básica (hover, zoom). Adicionar filtros de estado, ano e nível metálico via dropdowns permitiria exploração ad-hoc dos dados sem precisar rodar queries SQL.

**Análise Q3 com modelo preditivo**  
A questão Q3 (benefícios como variável de precificação) foi respondida com correlações descritivas. Um próximo passo seria construir um modelo de regressão (linear ou Random Forest) para quantificar o peso de cada categoria de benefício no prêmio final — usando o `data/exports/gold/analytics/q3_dataset_analitico_plano.csv` como conjunto de treino.

### 7.4 Segurança e Governança

**Criptografia em repouso nos buckets S3**  
A arquitetura prevê SSE (Server-Side Encryption) nos buckets S3, mas os templates CloudFormation atuais não configuram explicitamente a política de criptografia padrão. Adicionar `BucketEncryption` com `SSEAlgorithm: aws:kms` nos templates garante conformidade.

**Column-level security na Silver**  
A Silver contém dados de prêmio individualizados que poderiam ser considerados sensíveis em contextos regulatórios reais. Implementar Lake Formation com políticas de coluna permitiria, por exemplo, mascarar o `individualrate` para analistas sem permissão de acesso completo.

**Auditoria de acesso via CloudTrail**  
Para um ambiente de produção real, habilitar CloudTrail nos buckets S3 e no Athena Workgroup proveria rastreabilidade completa de quem acessou quais dados e quando.

---

*Documento elaborado pelo Grupo 05 em maio de 2026 como entrega final da disciplina Projeto Integrador (eEDB-015/2026-1) — Curso de Especialização em Big Data, Escola Politécnica da USP.*
