# src/ — Artefatos de Produção

Esta pasta contém os artefatos finais prontos para deploy e execução na AWS. Todo código aqui foi previamente validado nos notebooks de desenvolvimento em `scripts/`.

## Estrutura

```
src/
├── glue_jobs/               # Scripts PySpark deployados no AWS Glue
│   ├── landing_to_bronze.py
│   └── bronze_to_silver.py
├── lambdas/                 # Funções Lambda deployadas via deploy_lambda.sh
│   └── landing_zone_ingestion/
│       ├── handler.py
│       └── requirements.txt
└── .sql/                    # Queries SQL da camada Gold
    ├── create/              # DDL — criação das tabelas Iceberg
    ├── insert/              # DML — carga Silver → Gold
    └── analytics/           # Queries analíticas por questão de negócio
        ├── q1/              # Oncologia: Copay × Coinsurance
        ├── q2/              # Competição × Prêmio por estado
        ├── q3/              # Benefícios como variável de precificação
        └── q4/              # Tamanho da rede × Preço do plano
```

---

## glue_jobs/

Scripts PySpark executados pelo **AWS Glue** (Spark gerenciado). Cada arquivo corresponde a um Glue Job provisionado via CloudFormation.

| Script | Glue Job | Stack CloudFormation |
|---|---|---|
| `landing_to_bronze.py` | `eedb015-landing-to-bronze` | `04-glue-etl` |
| `bronze_to_silver.py` | `eedb015-bronze-to-silver` | `04-glue-etl` |

O deploy é feito pelo script `infrastructure/scripts/deploy_glue_jobs.sh`, que faz upload dos `.py` para o bucket Landing Zone e atualiza o stack CloudFormation correspondente.

> Para desenvolver ou modificar um Glue Job, trabalhe primeiro no notebook equivalente em `scripts/`. Quando a lógica estiver validada, traga as alterações para o script `.py` aqui.

---

## lambdas/

Funções Lambda que rodam fora do Spark. Cada subpasta é uma função independente com seu próprio `requirements.txt`.

| Subpasta | Função Lambda | Responsabilidade |
|---|---|---|
| `landing_zone_ingestion/` | `LandingZoneIngestionFunction` | Download dos CSVs do Kaggle e upload para a Landing Zone (S3) |

O deploy é feito pelo script `infrastructure/scripts/deploy_lambda.sh`, que empacota o código com as dependências em um ZIP e atualiza o stack `02-lambda-ingestion`.

---

## .sql/

Queries SQL que definem e carregam a camada Gold. A orquestração dessas queries via **AWS Step Functions** está planejada e ainda não implementada. Consulte [`scripts/silver_to_gold.md`](../scripts/silver_to_gold.md) para o design completo da camada.

### create/

DDL das tabelas Iceberg no database `eedb015_gold`. Todas usam `CREATE TABLE IF NOT EXISTS` (idempotente).

| Arquivo | Tabela |
|---|---|
| `create/dim_benefit_category.sql` | `eedb015_gold.dim_benefit_category` |
| `create/dim_geography.sql` | `eedb015_gold.dim_geography` |
| `create/dim_issuer.sql` | `eedb015_gold.dim_issuer` |
| `create/dim_network.sql` | `eedb015_gold.dim_network` |
| `create/dim_plan.sql` | `eedb015_gold.dim_plan` |
| `create/dim_time.sql` | `eedb015_gold.dim_time` |
| `create/fct_benefit_coverage.sql` | `eedb015_gold.fct_benefit_coverage` |
| `create/fct_market_competition.sql` | `eedb015_gold.fct_market_competition` |
| `create/fct_plan_premium.sql` | `eedb015_gold.fct_plan_premium` |

### insert/

DML de carga Silver → Gold. Cada arquivo lê de `eedb015_silver.*` e escreve na tabela Gold correspondente.

A ordem de execução respeita as dependências entre tabelas:

1. **Seeds** (sem dependência): `dim_time`, `dim_geography`, `dim_benefit_category`
2. **Dimensões derivadas** (paralelas): `dim_plan`, `dim_issuer`, `dim_network`
3. **Fatos** (dependem de `dim_plan`): `fct_plan_premium`, `fct_benefit_coverage`, `fct_market_competition`

### analytics/

Queries analíticas que respondem às questões de negócio do projeto, consumindo a camada Gold.

| Arquivo | Questão | Descrição |
|---|---|---|
| `analytics/q1/evolucao_copay_coinsurance.sql` | Q1 | Evolução anual de Copay × Coinsurance em tratamentos oncológicos por nível metálico |
| `analytics/q1/custo_total_paciente_cronico.sql` | Q1 | Custo total estimado (tratamento + prêmio) por nível metálico |
| `analytics/q2/competicao_vs_premio_por_estado.sql` | Q2 | Número de seguradoras vs. prêmio médio por estado e ano |
| `analytics/q2/evolucao_yoy_premio.sql` | Q2 | Variação % do prêmio de 2014 → 2016 por estado |
| `analytics/q3/correlacao_cobertura_premio.sql` | Q3 | Correlação entre cobertura de benefícios e prêmio por tipo/nível metálico |
| `analytics/q3/premio_por_categoria_beneficio.sql` | Q3 | Prêmio médio agrupado por categoria de benefício |
| `analytics/q4/premio_por_porte_rede.sql` | Q4 | Prêmio médio por porte de rede (small/medium/large) e estado |
| `analytics/q4/redes_pequenas_vs_media_estado.sql` | Q4 | Diferença entre prêmio de redes pequenas e a média estadual |
