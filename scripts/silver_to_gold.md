# Modelagem da Camada Gold — Health Insurance Marketplace

> **Contexto:** Este documento define o design completo da camada Gold (Refined/Delivery)
> do Data Lake do Projeto Integrador eEDB-015/2026-1. A Silver já está implementada;
> este plano é o insumo direto para queries `silver_to_gold` e para as Atividades 7 e 8.
>
> **Tecnologia:** Athena/Trino · Iceberg · AWS Glue (Spark SQL)

---

## Referências da Silver Layer

| Tabela Silver | Linhas | Colunas | Papel na Gold |
|---|---|---|---|
| `rate` | ~12,7 M | 26 | Prêmios mensais por plano/idade/área |
| `plan_attributes` | ~77 K | 178 | Catálogo mestre dos planos |
| `benefits_cost_sharing` | ~5 M | 34 | Benefícios e regras de custo compartilhado |
| `service_area` | ~42 K | 20 | Cobertura geográfica das seguradoras |
| `business_rules` | ~21 K | 25 | Regras de elegibilidade por plano |
| `crosswalk2015` | ~132 K | 23 | Linhagem dos planos 2014 → 2015 |
| `crosswalk2016` | ~150 K | 23 | Linhagem dos planos 2015 → 2016 |
| `network` | ~3,8 K | 16 | Metadados das redes de prestadores |

### Tipos e Valores Críticos das Colunas Silver

> ⚠️ **`rate.age` é INT (não STRING).** Valores válidos: 21–64. Aproximadamente 4,7% dos registros têm `age IS NULL` (linhas de família/agregadas). Filtro obrigatório: `r.age BETWEEN 21 AND 64`. **Nunca usar** `age = '27'` — sempre `age = 27`.

> ⚠️ **`rate.tobacco` — valores reais confirmados na Silver:**
>
> | Valor | Contagem | % |
> |---|---|---|
> | `'No Preference'` | 7.804.323 | 61,48% |
> | `'Tobacco User/Non-Tobacco User'` | 4.890.122 | 38,52% |
>
> O benchmark CMS (indivíduo padrão de 27 anos) usa **`tobacco = 'No Preference'`**. O valor `'Non-tobacco User'` **não existe** na Silver e retorna zero linhas quando usado como filtro.

> ⚠️ **`CAST AS STRING`**, não `CAST AS VARCHAR`. Em Spark SQL (Glue), `VARCHAR` não é tipo nativo — use sempre `CAST(coluna AS STRING)`.

### Regra crítica de JOIN entre tabelas Silver

```
rate.planid          → 14 chars (sem sufixo de variante)
plan_attributes.planid → 17 chars (com sufixo -XX)
benefits_cost_sharing.planid → 17 chars
business_rules.planid  → 17 chars
crosswalk.planid_*     → 14 chars
```

```sql
-- rate → plan_attributes / benefits_cost_sharing / business_rules
ON SUBSTR(pa.planid, 1, 14) = r.planid AND pa.businessyear = r.businessyear

-- plan_attributes → benefits_cost_sharing (join direto, ambos têm 17 chars)
ON bcs.planid = pa.planid AND bcs.businessyear = pa.businessyear

-- Filtro de variante base obrigatório (evita duplicatas CSR)
WHERE pa.csrvariationtype LIKE 'Standard%'
-- Alternativa equivalente via sufixo do PlanId:
-- WHERE RIGHT(pa.planid, 2) = '00'
```

> **Valores reais de `csrvariationtype` na Silver (confirmados na exploração):**
> - Variantes base (manter): `Standard Silver On Exchange Plan`, `Standard Silver Off Exchange Plan`, `Standard Bronze On Exchange Plan`, `Standard Bronze Off Exchange Plan`, `Standard Gold On Exchange Plan`, `Standard Gold Off Exchange Plan`, `Standard High On/Off Exchange Plan`, `Standard Low On/Off Exchange Plan`
> - Variantes CSR a excluir: `Zero Cost Sharing Plan Variation`, `Limited Cost Sharing Plan Variation`, `94% AV Level Silver Plan`, `87% AV Level Silver Plan`, `73% AV Level Silver Plan`
>
> O valor `'Standard Platinum Plan'` **não existe** nos dados — o filtro correto é `LIKE 'Standard%'`.

---

## Questões de Negócio a Responder

1. **Q1 — Oncologia:** Como evoluiu Copay × Coinsurance para Quimioterapia/Radioterapia (2014-2016)? Qual nível metálico minimiza a exposição financeira do paciente crônico?
2. **Q2 — Competição:** Correlação entre nº de seguradoras por estado e prêmio médio.
3. **Q3 — Benefícios × Preço:** Os benefícios são a principal variável de precificação? Como quantificá-los?
4. **Q4 — Rede × Preço:** Seguradoras com redes menores oferecem planos mais baratos?

---

## Atividade 7 — Modelagem Dimensional

### Escolha do Esquema

**Esquema Estrela (Star Schema).** Justificativa:
- Athena/Trino performa melhor com joins simples de 1-2 níveis.
- Ferramentas BI geram SQL mais eficiente contra estrelas.
- As dimensões têm cardinalidade moderada — a redundância textual é aceitável.

---

### Tabelas de Fato

#### `fct_plan_premium`

**Grão:** 1 linha por `(plan_id, business_year, state_code, age, tobacco_flag)`
**Fonte:** `rate` + `plan_attributes` + `business_rules`
**Volume estimado:** ~500 K linhas (redução de 12,7 M via agregação)

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` (FK) | `string` | → `dim_plan.plan_sk` |
| `geo_sk` (FK) | `string` | → `dim_geography.geo_sk` |
| `year_sk` (FK) | `integer` | → `dim_time.business_year` |
| `age` | `integer` | Idade em anos (21–64); NULLs excluídos via `r.age BETWEEN 21 AND 64` |
| `tobacco_flag` | `string` | `'No Preference'` / `'Tobacco User/Non-Tobacco User'` |
| `avg_individual_rate` | `double` | Prêmio médio mensal por indivíduo (USD) |
| `min_individual_rate` | `double` | Prêmio mínimo no período |
| `max_individual_rate` | `double` | Prêmio máximo no período |
| `rate_count` | `bigint` | Número de registros agregados |

---

#### `fct_benefit_coverage`

**Grão:** 1 linha por `(plan_id, benefit_name, business_year)`
**Fonte:** `benefits_cost_sharing` + `plan_attributes`

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` (FK) | `string` | → `dim_plan.plan_sk` |
| `benefit_sk` (FK) | `string` | → `dim_benefit_category.benefit_sk` |
| `year_sk` (FK) | `integer` | → `dim_time.business_year` |
| `is_covered` | `boolean` | Plano cobre este benefício |
| `is_ehb` | `boolean` | É Essential Health Benefit |
| `copay_inn_tier1` | `double` | Copagamento fixo em rede (USD; 0 = sem cobrança) |
| `coins_inn_tier1` | `double` | Coassegurado em rede (0.0–1.0; ex: 0.20 = 20%) |
| `copay_out_of_net` | `double` | Copagamento fora da rede (USD) |
| `coins_out_of_net` | `double` | Coassegurado fora da rede |
| `is_subj_to_ded` | `boolean` | Custo sujeito ao deductible primeiro |
| `limit_qty` | `integer` | Limite de sessões/visitas |
| `cost_type` | `string` | Derivado: `'copay'` / `'coinsurance'` / `'both'` / `'none'` |

---

#### `fct_market_competition`

**Grão:** 1 linha por `(state_code, business_year)`
**Fonte:** `rate` + `plan_attributes` + `service_area`

| Campo | Tipo | Descrição |
|---|---|---|
| `geo_sk` (FK) | `string` | → `dim_geography.geo_sk` |
| `year_sk` (FK) | `integer` | → `dim_time.business_year` |
| `num_active_issuers` | `bigint` | Nº de seguradoras com planos ativos |
| `num_active_plans` | `bigint` | Total de planos disponíveis no estado |
| `avg_premium_individual` | `double` | Prêmio médio (27 anos, não fumante) em USD |
| `median_premium_individual` | `double` | Prêmio mediano (p50) |
| `competition_tier` | `string` | `'monopoly'`(1) / `'low'`(2-3) / `'moderate'`(4-6) / `'high'`(7+) |

---

### Tabelas de Dimensão

#### `dim_plan`

**PK:** `plan_sk = CONCAT(SUBSTR(plan_id, 1, 14), '_', business_year)`

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` | `string` | Surrogate key |
| `plan_id_base` | `string` | HIOS Plan ID 14 chars (sem sufixo) |
| `plan_id_full` | `string` | HIOS Plan ID 17 chars (com variante) |
| `business_year` | `integer` | Ano do plano (2014, 2015, 2016) |
| `plan_name` | `string` | Nome de marketing |
| `metal_level` | `string` | Bronze / Silver / Gold / Platinum / Catastrophic |
| `plan_type` | `string` | HMO / PPO / EPO / POS |
| `issuer_id` | `string` | ID da seguradora (5 dígitos HIOS) |
| `state_code` | `string` | Estado (2 chars) |
| `network_id` | `string` | ID da rede de prestadores |
| `service_area_id` | `string` | ID da área de serviço |
| `market_coverage` | `string` | Individual / Small Group |
| `is_dental_only` | `boolean` | Plano exclusivamente odontológico |
| `is_new_plan` | `boolean` | Plano sem histórico anterior |
| `wellness_program` | `boolean` | Oferece programa de bem-estar |
| `national_network` | `boolean` | Rede de cobertura nacional |
| `ehb_pct_premium` | `double` | % do prêmio destinado a EHBs |
| `moop_individual` | `double` | Teto máximo de desembolso anual — indivíduo (USD) |
| `deductible_individual` | `double` | Franquia anual — indivíduo (USD) |
| `plan_lineage_id_2014` | `string` | planid equivalente em 2014 (via crosswalk; null se novo) |
| `plan_lineage_id_2015` | `string` | planid equivalente em 2015 |
| `plan_lineage_id_2016` | `string` | planid equivalente em 2016 |
| `network_plan_count` | `integer` | Planos que compartilham a mesma rede (proxy de tamanho) |

---

#### `dim_geography`

**PK:** `geo_sk = state_code`
**Hierarquia:** `census_division` → `census_region` → `state_code`

| Campo | Tipo | Descrição |
|---|---|---|
| `geo_sk` | `string` | Chave primária |
| `state_code` | `string` | Sigla do estado (AK, AL, ...) |
| `state_name` | `string` | Nome completo (enriquecimento estático) |
| `census_region` | `string` | Northeast / Midwest / South / West |
| `census_division` | `string` | Subdivisão do Censo |
| `num_counties_covered` | `integer` | Condados com cobertura registrada na Silver |

---

#### `dim_benefit_category`

**PK:** `benefit_sk = MD5(benefit_name)` ou slug normalizado

| Campo | Tipo | Descrição |
|---|---|---|
| `benefit_sk` | `string` | Chave primária |
| `benefit_name` | `string` | Nome original (ex: `'Chemotherapy'`) |
| `benefit_category` | `string` | Categoria analítica (ver tabela abaixo) |
| `is_oncology` | `boolean` | Benefício oncológico |
| `is_preventive` | `boolean` | Benefício preventivo |
| `is_mental_health` | `boolean` | Saúde mental |
| `is_chronic` | `boolean` | Tratamento crônico/recorrente |
| `is_ehb_standard` | `boolean` | EHB padrão pelo CMS |

**Mapeamento de categorias:**

| Categoria | Exemplos de BenefitName |
|---|---|
| `oncology` | Chemotherapy, Radiation Therapy, Infusion Therapy |
| `preventive` | Preventive Care/Screening/Immunization, Well Baby/Well Child Visits |
| `mental_health` | Mental/Behavioral Health Outpatient/Inpatient |
| `primary_care` | Primary Care Visit to Treat an Injury or Illness |
| `specialist` | Specialist Visit |
| `emergency` | Emergency Room Services, Urgent Care Centers |
| `pharmacy` | Generic, Preferred Brand, Non-Preferred Brand, Specialty Drug |
| `maternity` | Maternity and Newborn Care |
| `chronic_mgmt` | Home Health Care, Skilled Nursing, Rehabilitation |
| `dental_vision` | Dental Care, Eye Exam |
| `other` | demais |

---

#### `dim_issuer`

**PK:** `issuer_sk = issuer_id || '_' || business_year`

| Campo | Tipo | Descrição |
|---|---|---|
| `issuer_sk` | `string` | Surrogate key |
| `issuer_id` | `string` | ID único da seguradora (5 dígitos) |
| `business_year` | `integer` | Ano de referência |
| `state_code` | `string` | Estado principal de operação |
| `num_plans_offered` | `integer` | Total de planos oferecidos |
| `num_networks` | `integer` | Número de redes distintas |
| `avg_network_size` | `integer` | Média de planos por rede |

---

#### `dim_network`

**PK:** `network_sk = network_id || '_' || business_year`

| Campo | Tipo | Descrição |
|---|---|---|
| `network_sk` | `string` | Surrogate key |
| `network_id` | `string` | ID da rede |
| `network_name` | `string` | Nome descritivo |
| `issuer_id` | `string` | Seguradora proprietária |
| `state_code` | `string` | Estado de operação |
| `business_year` | `integer` | Ano |
| `plan_count` | `integer` | Planos que usam esta rede |
| `network_size_tier` | `string` | `'small'`(1-5) / `'medium'`(6-20) / `'large'`(21+) |

---

#### `dim_time`

**PK:** `business_year`

| Campo | Tipo | Descrição |
|---|---|---|
| `business_year` | `integer` | Ano fiscal (2014, 2015, 2016) |
| `year_label` | `string` | Rótulo para exibição |
| `aca_phase` | `string` | `'Year 1'` / `'Year 2'` / `'Year 3'` |

---

### Cardinalidade dos Relacionamentos

```
dim_time (3 linhas)
    │ 1
    │ N
fct_plan_premium ─────N:1─── dim_plan (1 plano : N linhas por faixa etária)
    │
    └─N:1─── dim_geography (1 estado : N planos)

fct_benefit_coverage ─N:1─── dim_plan
                    └─N:1─── dim_benefit_category (1 benefício : N planos)
                    └─N:1─── dim_time

fct_market_competition ─N:1─── dim_geography
                       └─N:1─── dim_time

dim_plan ─N:1─── dim_issuer  (N planos : 1 seguradora)
dim_plan ─N:1─── dim_network (N planos : 1 rede)
```

---

### Índices / Particionamento Iceberg

| Tabela | Partição Iceberg | Sort Order |
|---|---|---|
| `fct_plan_premium` | `business_year` | `state_code`, `metal_level` |
| `fct_benefit_coverage` | `business_year` | `benefit_category`, `state_code` |
| `fct_market_competition` | `business_year` | `state_code` |
| `dim_plan` | `business_year` | `metal_level`, `issuer_id` |

---

## DDL — Criação das Tabelas Iceberg

> Execute estes `CREATE TABLE` antes dos `INSERT INTO`. Em Glue Spark Jobs, use `spark.sql(...)` com cada bloco abaixo.
> O location deve apontar para o bucket Gold configurado no ambiente (`s3://637423524537-eedb015-gold/gold/<tabela>/`).

### Tabelas de Fato

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.fct_plan_premium (
    plan_sk              STRING,
    geo_sk               STRING,
    year_sk              INT,
    age                  INT,
    tobacco_flag         STRING,
    avg_individual_rate  DOUBLE,
    min_individual_rate  DOUBLE,
    max_individual_rate  DOUBLE,
    rate_count           BIGINT
)

PARTITIONED BY (year_sk)
LOCATION 's3://637423524537-eedb015-gold/gold/fct_plan_premium/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.fct_benefit_coverage (
    plan_sk         STRING,
    benefit_sk      STRING,
    year_sk         INT,
    is_covered      BOOLEAN,
    is_ehb          BOOLEAN,
    copay_inn_tier1 DOUBLE,
    coins_inn_tier1 DOUBLE,
    copay_out_of_net DOUBLE,
    coins_out_of_net DOUBLE,
    is_subj_to_ded  BOOLEAN,
    limit_qty       INT,
    cost_type       STRING
)

PARTITIONED BY (year_sk)
LOCATION 's3://637423524537-eedb015-gold/gold/fct_benefit_coverage/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.fct_market_competition (
    geo_sk                    STRING,
    year_sk                   INT,
    num_active_issuers        BIGINT,
    num_active_plans          BIGINT,
    avg_premium_individual    DOUBLE,
    median_premium_individual DOUBLE,
    competition_tier          STRING
)

PARTITIONED BY (year_sk)
LOCATION 's3://637423524537-eedb015-gold/gold/fct_market_competition/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

### Tabelas de Dimensão

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_plan (
    plan_sk               STRING,
    plan_id_base          STRING,
    plan_id_full          STRING,
    business_year         INT,
    plan_name             STRING,
    metal_level           STRING,
    plan_type             STRING,
    issuer_id             STRING,
    state_code            STRING,
    network_id            STRING,
    service_area_id       STRING,
    market_coverage       STRING,
    is_dental_only        BOOLEAN,
    is_new_plan           BOOLEAN,
    wellness_program      BOOLEAN,
    national_network      BOOLEAN,
    ehb_pct_premium       DOUBLE,
    moop_individual       DOUBLE,
    deductible_individual DOUBLE,
    plan_lineage_id_2014  STRING,
    plan_lineage_id_2015  STRING,
    plan_lineage_id_2016  STRING,
    network_plan_count    INT
)

PARTITIONED BY (business_year)
LOCATION 's3://637423524537-eedb015-gold/gold/dim_plan/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_geography (
    geo_sk               STRING,
    state_code           STRING,
    state_name           STRING,
    census_region        STRING,
    census_division      STRING,
    num_counties_covered INT
)

LOCATION 's3://637423524537-eedb015-gold/gold/dim_geography/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_benefit_category (
    benefit_sk       STRING,
    benefit_name     STRING,
    benefit_category STRING,
    is_oncology      BOOLEAN,
    is_preventive    BOOLEAN,
    is_mental_health BOOLEAN,
    is_chronic       BOOLEAN,
    is_ehb_standard  BOOLEAN
)

LOCATION 's3://637423524537-eedb015-gold/gold/dim_benefit_category/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_issuer (
    issuer_sk        STRING,
    issuer_id        STRING,
    business_year    INT,
    state_code       STRING,
    num_plans_offered INT,
    num_networks     INT,
    avg_network_size INT
)

PARTITIONED BY (business_year)
LOCATION 's3://637423524537-eedb015-gold/gold/dim_issuer/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_network (
    network_sk        STRING,
    network_id        STRING,
    network_name      STRING,
    issuer_id         STRING,
    state_code        STRING,
    business_year     INT,
    plan_count        INT,
    network_size_tier STRING
)

PARTITIONED BY (business_year)
LOCATION 's3://637423524537-eedb015-gold/gold/dim_network/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

```sql
CREATE TABLE IF NOT EXISTS eedb015_gold.dim_time (
    business_year INT,
    year_label    STRING,
    aca_phase     STRING
)

LOCATION 's3://637423524537-eedb015-gold/gold/dim_time/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
```

---

## Mapeamento Silver → Gold

### `fct_plan_premium`

```sql
INSERT INTO eedb015_gold.fct_plan_premium
SELECT
    CONCAT(SUBSTR(pa.planid, 1, 14), '_', CAST(r.businessyear AS VARCHAR)) AS plan_sk,
    r.statecode                                                             AS geo_sk,
    r.businessyear                                                          AS year_sk,
    r.age,
    r.tobacco                                                               AS tobacco_flag,
    AVG(r.individualrate)                                                   AS avg_individual_rate,
    MIN(r.individualrate)                                                   AS min_individual_rate,
    MAX(r.individualrate)                                                   AS max_individual_rate,
    COUNT(*)                                                                AS rate_count
FROM eedb015_silver.rate r
JOIN eedb015_silver.plan_attributes pa
    ON SUBSTR(pa.planid, 1, 14) = r.planid
   AND pa.businessyear = r.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14)
   AND br.businessyear = pa.businessyear
WHERE r.individualrate > 0
  AND r.individualrate < 3000
  AND r.age BETWEEN 21 AND 64
  AND br.dentalonlyplan = FALSE
  AND br.marketcoverage = 'Individual'
GROUP BY 1, 2, 3, 4, 5
```

**Reduções:** ~12,7 M → ~500 K linhas via agregação por faixa etária.
**Filtros:** outliers de preço removidos (`0 < rate < 3000`), planos dentários excluídos, variante CSR base selecionada.

---

### `fct_benefit_coverage`

```sql
INSERT INTO eedb015_gold.fct_benefit_coverage
SELECT
    CONCAT(SUBSTR(bcs.planid, 1, 14), '_', CAST(bcs.businessyear AS VARCHAR)) AS plan_sk,
    md5(bcs.benefitname)                                                         AS benefit_sk,
    bcs.businessyear                                                             AS year_sk,
    bcs.iscovered,
    bcs.isehb,
    bcs.copayinntier1                                                            AS copay_inn_tier1,
    bcs.coinsinntier1                                                            AS coins_inn_tier1,
    bcs.copayoutofnet                                                            AS copay_out_of_net,
    bcs.coinsoutofnet                                                            AS coins_out_of_net,
    bcs.issubjtodedtier1                                                         AS is_subj_to_ded,
    bcs.limitqty                                                                 AS limit_qty,
    CASE
        WHEN bcs.copayinntier1 IS NOT NULL AND bcs.coinsinntier1 IS NOT NULL THEN 'both'
        WHEN bcs.copayinntier1 IS NOT NULL THEN 'copay'
        WHEN bcs.coinsinntier1 IS NOT NULL THEN 'coinsurance'
        ELSE 'none'
    END AS cost_type
FROM eedb015_silver.benefits_cost_sharing bcs
JOIN eedb015_silver.plan_attributes pa
    ON pa.planid = bcs.planid
   AND pa.businessyear = bcs.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
```

---

### `fct_market_competition`

```sql
INSERT INTO eedb015_gold.fct_market_competition
SELECT
    r.statecode                                                  AS geo_sk,
    r.businessyear                                               AS year_sk,
    COUNT(DISTINCT pa.IssuerId)                                  AS num_active_issuers,
    COUNT(DISTINCT SUBSTR(pa.planid, 1, 14))                     AS num_active_plans,
    ROUND(AVG(CASE WHEN r.age = 27 AND r.tobacco = 'No Preference'
                   THEN r.individualrate END), 2)                AS avg_premium_individual,
    percentile_approx(CASE WHEN r.age = 27 AND r.tobacco = 'No Preference'
                           THEN r.individualrate END, 0.5)       AS median_premium_individual,
    CASE
        WHEN COUNT(DISTINCT pa.IssuerId) = 1 THEN 'monopoly'
        WHEN COUNT(DISTINCT pa.IssuerId) <= 3 THEN 'low'
        WHEN COUNT(DISTINCT pa.IssuerId) <= 6 THEN 'moderate'
        ELSE 'high'
    END AS competition_tier
FROM eedb015_silver.rate r
JOIN eedb015_silver.plan_attributes pa
    ON SUBSTR(pa.planid, 1, 14) = r.planid
   AND pa.businessyear = r.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14)
   AND br.businessyear = pa.businessyear
   AND br.dentalonlyplan = FALSE
   AND br.marketcoverage = 'Individual'
WHERE r.individualrate > 0 AND r.individualrate < 3000
  AND r.age BETWEEN 21 AND 64
GROUP BY r.statecode, r.businessyear
```

> **Padronização de benchmark de preço:** `age = 27` (INT), `tobacco = 'No Preference'` — valores reais na Silver (padrão CMS para comparação entre estados).

---

### `dim_plan`

```sql
INSERT INTO eedb015_gold.dim_plan
SELECT
    CONCAT(SUBSTR(pa.planid, 1, 14), '_', CAST(pa.businessyear AS VARCHAR)) AS plan_sk,
    SUBSTR(pa.planid, 1, 14)                                                 AS plan_id_base,
    pa.planid                                                                AS plan_id_full,
    pa.businessyear,
    pa.PlanMarketingName                                                     AS plan_name,
    pa.MetalLevel                                                            AS metal_level,
    pa.PlanType                                                              AS plan_type,
    pa.IssuerId                                                              AS issuer_id,
    pa.statecode                                                             AS state_code,
    pa.NetworkId                                                             AS network_id,
    pa.ServiceAreaId                                                         AS service_area_id,
    br.marketcoverage                                                        AS market_coverage,
    COALESCE(br.dentalonlyplan, FALSE)                                       AS is_dental_only,
    COALESCE(pa.IsNewPlan, FALSE)                                            AS is_new_plan,
    COALESCE(pa.WellnessProgramOffered, FALSE)                               AS wellness_program,
    CAST(COALESCE(pa.NationalNetwork, 0) AS BOOLEAN)                         AS national_network,
    pa.EHBPercentTotalPremium                                                AS ehb_pct_premium,
    pa.MEHBInnTier1IndividualMOOP                                            AS moop_individual,
    pa.MEHBDedInnTier1Individual                                             AS deductible_individual,
    c15.planid_2014                                                          AS plan_lineage_id_2014,
    c15.planid_2015                                                          AS plan_lineage_id_2015,
    c16.planid_2015_ref                                                      AS plan_lineage_id_2016,
    net_agg.plan_count                                                       AS network_plan_count
FROM eedb015_silver.plan_attributes pa
LEFT JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14) AND br.businessyear = pa.businessyear
LEFT JOIN (
    SELECT planid_2015, MAX(planid_2014) AS planid_2014
    FROM eedb015_silver.crosswalk2015
    GROUP BY planid_2015
) c15 ON c15.planid_2015 = SUBSTR(pa.planid, 1, 14) AND pa.businessyear = 2015
LEFT JOIN (
    SELECT planid_2016, MAX(planid_2015) AS planid_2015_ref
    FROM eedb015_silver.crosswalk2016
    GROUP BY planid_2016
) c16 ON c16.planid_2016 = SUBSTR(pa.planid, 1, 14) AND pa.businessyear = 2016
LEFT JOIN (
    SELECT NetworkId, businessyear, COUNT(DISTINCT planid) AS plan_count
    FROM eedb015_silver.plan_attributes
    GROUP BY NetworkId, businessyear
) net_agg ON net_agg.NetworkId = pa.NetworkId AND net_agg.businessyear = pa.businessyear
WHERE pa.csrvariationtype LIKE 'Standard%'
```

---

### `dim_time`

```sql
INSERT INTO eedb015_eedb015_gold.dim_time VALUES
    (2014, '2014', 'Year 1'),
    (2015, '2015', 'Year 2'),
    (2016, '2016', 'Year 3')
```

---

### `dim_geography`

```sql
INSERT INTO eedb015_gold.dim_geography
WITH geo_static AS (
    SELECT state_code, state_name, census_region, census_division
    FROM (VALUES
        ('AK', 'Alaska',               'West',      'Pacific'),
        ('AL', 'Alabama',              'South',     'East South Central'),
        ('AR', 'Arkansas',             'South',     'West South Central'),
        ('AZ', 'Arizona',              'West',      'Mountain'),
        ('CA', 'California',           'West',      'Pacific'),
        ('CO', 'Colorado',             'West',      'Mountain'),
        ('CT', 'Connecticut',          'Northeast', 'New England'),
        ('DC', 'District of Columbia', 'South',     'South Atlantic'),
        ('DE', 'Delaware',             'South',     'South Atlantic'),
        ('FL', 'Florida',              'South',     'South Atlantic'),
        ('GA', 'Georgia',              'South',     'South Atlantic'),
        ('HI', 'Hawaii',               'West',      'Pacific'),
        ('IA', 'Iowa',                 'Midwest',   'West North Central'),
        ('ID', 'Idaho',                'West',      'Mountain'),
        ('IL', 'Illinois',             'Midwest',   'East North Central'),
        ('IN', 'Indiana',              'Midwest',   'East North Central'),
        ('KS', 'Kansas',               'Midwest',   'West North Central'),
        ('KY', 'Kentucky',             'South',     'East South Central'),
        ('LA', 'Louisiana',            'South',     'West South Central'),
        ('MA', 'Massachusetts',        'Northeast', 'New England'),
        ('MD', 'Maryland',             'South',     'South Atlantic'),
        ('ME', 'Maine',                'Northeast', 'New England'),
        ('MI', 'Michigan',             'Midwest',   'East North Central'),
        ('MN', 'Minnesota',            'Midwest',   'West North Central'),
        ('MO', 'Missouri',             'Midwest',   'West North Central'),
        ('MS', 'Mississippi',          'South',     'East South Central'),
        ('MT', 'Montana',              'West',      'Mountain'),
        ('NC', 'North Carolina',       'South',     'South Atlantic'),
        ('ND', 'North Dakota',         'Midwest',   'West North Central'),
        ('NE', 'Nebraska',             'Midwest',   'West North Central'),
        ('NH', 'New Hampshire',        'Northeast', 'New England'),
        ('NJ', 'New Jersey',           'Northeast', 'Middle Atlantic'),
        ('NM', 'New Mexico',           'West',      'Mountain'),
        ('NV', 'Nevada',               'West',      'Mountain'),
        ('NY', 'New York',             'Northeast', 'Middle Atlantic'),
        ('OH', 'Ohio',                 'Midwest',   'East North Central'),
        ('OK', 'Oklahoma',             'South',     'West South Central'),
        ('OR', 'Oregon',               'West',      'Pacific'),
        ('PA', 'Pennsylvania',         'Northeast', 'Middle Atlantic'),
        ('RI', 'Rhode Island',         'Northeast', 'New England'),
        ('SC', 'South Carolina',       'South',     'South Atlantic'),
        ('SD', 'South Dakota',         'Midwest',   'West North Central'),
        ('TN', 'Tennessee',            'South',     'East South Central'),
        ('TX', 'Texas',                'South',     'West South Central'),
        ('UT', 'Utah',                 'West',      'Mountain'),
        ('VA', 'Virginia',             'South',     'South Atlantic'),
        ('VT', 'Vermont',              'Northeast', 'New England'),
        ('WA', 'Washington',           'West',      'Pacific'),
        ('WI', 'Wisconsin',            'Midwest',   'East North Central'),
        ('WV', 'West Virginia',        'South',     'South Atlantic'),
        ('WY', 'Wyoming',              'West',      'Mountain')
    ) AS t(state_code, state_name, census_region, census_division)
),
county_counts AS (
    SELECT statecode AS state_code, COUNT(DISTINCT county) AS num_counties_covered
    FROM eedb015_silver.service_area
    WHERE county IS NOT NULL
    GROUP BY statecode
)
SELECT
    g.state_code                        AS geo_sk,
    g.state_code,
    g.state_name,
    g.census_region,
    g.census_division,
    COALESCE(c.num_counties_covered, 0) AS num_counties_covered
FROM geo_static g
LEFT JOIN county_counts c ON c.state_code = g.state_code
```

---

### `dim_benefit_category`

```sql
INSERT INTO eedb015_gold.dim_benefit_category
WITH benefit_base AS (
    SELECT
        benefitname,
        BOOL_OR(isehb) AS is_ehb_standard
    FROM eedb015_silver.benefits_cost_sharing
    GROUP BY benefitname
)
SELECT
    md5(benefitname) AS benefit_sk,
    benefitname      AS benefit_name,
    CASE
        WHEN benefitname IN ('Chemotherapy', 'Radiation Therapy', 'Infusion Therapy')
            THEN 'oncology'
        WHEN benefitname LIKE '%Preventive%'
          OR benefitname LIKE '%Well Baby%'
          OR benefitname LIKE '%Well Child%'
            THEN 'preventive'
        WHEN benefitname LIKE '%Mental%'
          OR benefitname LIKE '%Behavioral%'
          OR benefitname LIKE '%Substance Abuse%'
            THEN 'mental_health'
        WHEN benefitname LIKE '%Primary Care%'
            THEN 'primary_care'
        WHEN benefitname = 'Specialist Visit'
            THEN 'specialist'
        WHEN benefitname LIKE '%Emergency%'
          OR benefitname LIKE '%Urgent Care%'
          OR benefitname LIKE '%Ambulance%'
            THEN 'emergency'
        WHEN benefitname LIKE '%Drug%'
          OR benefitname LIKE '%Drugs%'
            THEN 'pharmacy'
        WHEN benefitname LIKE '%Maternity%'
          OR benefitname LIKE '%Newborn%'
            THEN 'maternity'
        WHEN benefitname LIKE '%Home Health%'
          OR benefitname LIKE '%Skilled Nursing%'
          OR benefitname LIKE '%Rehabilitat%'
          OR benefitname LIKE '%Habilitat%'
            THEN 'chronic_mgmt'
        WHEN benefitname LIKE '%Dental%'
          OR benefitname LIKE '%Eye%'
          OR benefitname LIKE '%Vision%'
          OR benefitname LIKE '%Orthodont%'
            THEN 'dental_vision'
        ELSE 'other'
    END AS benefit_category,
    benefitname IN ('Chemotherapy', 'Radiation Therapy', 'Infusion Therapy')
        AS is_oncology,
    (benefitname LIKE '%Preventive%'
     OR benefitname LIKE '%Well Baby%'
     OR benefitname LIKE '%Well Child%')
        AS is_preventive,
    (benefitname LIKE '%Mental%'
     OR benefitname LIKE '%Behavioral%'
     OR benefitname LIKE '%Substance Abuse%')
        AS is_mental_health,
    (benefitname LIKE '%Home Health%'
     OR benefitname LIKE '%Skilled Nursing%'
     OR benefitname LIKE '%Rehabilitat%')
        AS is_chronic,
    is_ehb_standard
FROM benefit_base
```

---

### `dim_issuer`

```sql
INSERT INTO eedb015_gold.dim_issuer
SELECT
    pa.issuerid || '_' || CAST(pa.businessyear AS VARCHAR)    AS issuer_sk,
    pa.issuerid,
    pa.businessyear,
    pa.statecode                                              AS state_code,
    COUNT(DISTINCT SUBSTR(pa.planid, 1, 14))                  AS num_plans_offered,
    COUNT(DISTINCT pa.networkid)                              AS num_networks,
    CAST(ROUND(
        COUNT(DISTINCT SUBSTR(pa.planid, 1, 14)) * 1.0
        / NULLIF(COUNT(DISTINCT pa.networkid), 0)
    , 0) AS INT)                                              AS avg_network_size
FROM eedb015_silver.plan_attributes pa
WHERE RIGHT(pa.planid, 2) = '00'
GROUP BY pa.issuerid, pa.businessyear, pa.statecode
```

---

### `dim_network`

```sql
INSERT INTO eedb015_gold.dim_network
WITH net_plan_count AS (
    SELECT networkid, businessyear, COUNT(DISTINCT SUBSTR(planid, 1, 14)) AS plan_count
    FROM eedb015_silver.plan_attributes
    WHERE RIGHT(planid, 2) = '00'
    GROUP BY networkid, businessyear
)
SELECT
    n.networkid || '_' || CAST(n.businessyear AS VARCHAR)      AS network_sk,
    n.networkid,
    n.networkname                                              AS network_name,
    n.issuerid                                                 AS issuer_id,
    n.statecode                                                AS state_code,
    n.businessyear,
    COALESCE(npc.plan_count, 0)                                AS plan_count,
    CASE
        WHEN COALESCE(npc.plan_count, 0) <= 5  THEN 'small'
        WHEN COALESCE(npc.plan_count, 0) <= 20 THEN 'medium'
        ELSE 'large'
    END AS network_size_tier
FROM eedb015_silver.network n
LEFT JOIN net_plan_count npc
    ON npc.networkid = n.networkid AND npc.businessyear = n.businessyear
```

---

## Notas de Implementação

### `rate.age` — INT, não STRING

A coluna `age` na tabela Silver `rate` é do tipo **INT** (valores 21–64). Linhas com `age IS NULL` (~4,7%) representam tarifas de família/agregadas e devem ser excluídas com `r.age BETWEEN 21 AND 64`. **Nunca comparar com string** (`age = '27'`): em Spark SQL a comparação silenciosa produz zero linhas.

### `rate.tobacco` — valores reais na Silver

Os únicos valores presentes na Silver são `'No Preference'` (61,5%) e `'Tobacco User/Non-Tobacco User'` (38,5%). O filtro de benchmark CMS é `tobacco = 'No Preference'`. O valor `'Non-tobacco User'` não existe nos dados e deve ser removido de qualquer query.

### `dim_geography` — seed estática obrigatória

As colunas `state_name`, `census_region` e `census_division` não existem nas tabelas Silver. O INSERT acima usa uma cláusula `VALUES` hardcoded com os 51 territórios (50 estados + DC) e faz LEFT JOIN com `service_area` para derivar `num_counties_covered` diretamente da Silver.

### `dim_benefit_category` — derivada da Silver, não seed pura

Embora as categorias analíticas (`is_oncology`, `is_preventive`, etc.) sejam lógica de negócio, o INSERT acima usa `SELECT DISTINCT benefitname` da Silver para garantir que todos os nomes reais de benefícios sejam capturados. A categorização é feita via `CASE/LIKE`, evitando listas estáticas incompletas.

### `dim_time` — seed mínima

Apenas 3 linhas (2014, 2015, 2016). Inserir com `VALUES` antes de qualquer outro job Gold.

### `dim_issuer` e `dim_network` — derivadas da Silver

Ambas derivam diretamente de `plan_attributes` e `network`. Inserir após `dim_plan` pois dependem da mesma lógica de filtro de variante (`RIGHT(planid, 2) = '00'`).

### `md5()` — Spark SQL vs. Athena/Trino

O job Glue usa Spark SQL, onde `md5(string)` retorna string hex diretamente. Para reproduzir a mesma chave em queries Athena/Trino, use `to_hex(md5(to_utf8(benefit_name)))`.

---

## Queries Analíticas — Camada Gold

### Q1 — Evolução Copay × Coinsurance em Tratamentos Oncológicos

```sql
-- Evolução anual por nível metálico
SELECT
    fbc.year_sk                                                       AS ano,
    dp.metal_level                                                    AS nivel_metalico,
    dbc.benefit_name                                                  AS beneficio,
    COUNT(*)                                                          AS total_planos,
    SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                  AS planos_com_cobertura,
    ROUND(100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                              AS pct_cobertura,
    ROUND(AVG(CASE WHEN fbc.is_covered THEN fbc.copay_inn_tier1 END), 2)
                                                                      AS avg_copay_usd,
    ROUND(AVG(CASE WHEN fbc.is_covered THEN fbc.coins_inn_tier1 END) * 100, 2)
                                                                      AS avg_coinsurance_pct,
    ROUND(AVG(CASE WHEN fbc.is_subj_to_ded
                   THEN dp.deductible_individual ELSE 0.0 END), 2)   AS avg_deductible_efetivo
FROM eedb015_gold.fct_benefit_coverage fbc
JOIN eedb015_gold.dim_plan dp         ON dp.plan_sk = fbc.plan_sk
JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
WHERE dbc.is_oncology = TRUE
  AND dp.is_dental_only = FALSE
  AND dp.market_coverage = 'Individual'
  AND dp.metal_level IN ('Bronze', 'Silver', 'Gold', 'Platinum')
GROUP BY 1, 2, 3
ORDER BY dbc.benefit_name, dp.metal_level, fbc.year_sk
```

```sql
-- Qual nível metálico minimiza o custo total do paciente crônico?
-- (proxy: 12 sessões/ano × custo por sessão + prêmio anual)
WITH oncology_cost AS (
    SELECT
        fbc.year_sk,
        dp.metal_level,
        dp.plan_sk,
        COALESCE(fbc.copay_inn_tier1,
                 fbc.coins_inn_tier1 * dp.moop_individual, 0) AS estimated_session_cost,
        dp.moop_individual
    FROM eedb015_gold.fct_benefit_coverage fbc
    JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = fbc.plan_sk
    JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
    WHERE dbc.benefit_name IN ('Chemotherapy', 'Infusion Therapy')
      AND fbc.is_covered = TRUE
      AND dp.is_dental_only = FALSE
),
premium_27 AS (
    SELECT plan_sk, year_sk, avg_individual_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
)
SELECT
    oc.year_sk                                                       AS ano,
    oc.metal_level                                                   AS nivel_metalico,
    ROUND(AVG(oc.estimated_session_cost * 12), 2)                   AS custo_tratamento_anual_est,
    ROUND(AVG(p.avg_individual_rate * 12), 2)                       AS custo_premio_anual,
    ROUND(AVG(oc.moop_individual), 2)                               AS moop_individual_medio,
    ROUND(AVG(
        LEAST(oc.estimated_session_cost * 12, oc.moop_individual)
        + p.avg_individual_rate * 12
    ), 2)                                                            AS custo_total_paciente_est
FROM oncology_cost oc
JOIN premium_27 p ON p.plan_sk = oc.plan_sk AND p.year_sk = oc.year_sk
GROUP BY 1, 2
ORDER BY oc.year_sk, custo_total_paciente_est
```

---

### Q2 — Correlação Competição × Prêmio Médio por Estado

```sql
-- Visão anual: número de seguradoras vs prêmio médio por estado
SELECT
    mc.year_sk                               AS ano,
    dg.state_code                            AS estado,
    dg.state_name,
    dg.census_region                         AS regiao,
    mc.num_active_issuers                    AS num_seguradoras,
    mc.competition_tier                      AS nivel_competicao,
    ROUND(mc.avg_premium_individual, 2)      AS premio_medio_usd,
    ROUND(mc.median_premium_individual, 2)   AS premio_mediano_usd,
    mc.num_active_plans                      AS total_planos
FROMeedb015_goldfct_market_competition mc
JOIN eedb015_gold.dim_geography dg ON dg.geo_sk = mc.geo_sk
ORDER BY mc.year_sk, mc.num_active_issuers DESC
```

```sql
-- Evolução YoY: variação do prêmio vs número de seguradoras
SELECT
    dg.state_code,
    dg.state_name,
    MAX(CASE WHEN mc.year_sk = 2014 THEN mc.num_active_issuers END)    AS issuers_2014,
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.num_active_issuers END)    AS issuers_2016,
    MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END) AS premio_2014,
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END) AS premio_2016,
    ROUND(
        (MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END) -
         MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END))
        / NULLIF(MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END), 0) * 100,
        2
    ) AS variacao_premio_pct
FROM eedb015_gold.fct_market_competition mc
JOIN eedb015_gold.dim_geography dg ON dg.geo_sk = mc.geo_sk
GROUP BY dg.state_code, dg.state_name
ORDER BY variacao_premio_pct DESC
```

---

### Q3 — Benefícios como Variável de Precificação

```sql
-- Score de cobertura por plano vs prêmio — correlação por nível metálico
WITH benefit_score AS (
    SELECT
        fbc.plan_sk,
        fbc.year_sk,
        COUNT(*)                                                          AS total_benefits,
        SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                  AS covered_benefits,
        ROUND(100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)
              / COUNT(*), 1)                                              AS pct_covered,
        ROUND(AVG(COALESCE(fbc.copay_inn_tier1, 0)), 2)                  AS avg_copay,
        ROUND(AVG(COALESCE(fbc.coins_inn_tier1, 0)), 4)                  AS avg_coinsurance
    FROM eedb015_gold.fct_benefit_coverage fbc
    GROUP BY 1, 2
),
plan_price AS (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    dp.metal_level,
    dp.plan_type,
    bs.year_sk                                                    AS ano,
    ROUND(AVG(bs.covered_benefits), 1)                           AS media_beneficios_cobertos,
    ROUND(AVG(bs.pct_covered), 1)                                AS media_pct_cobertura,
    ROUND(AVG(bs.avg_copay), 2)                                  AS media_copay_geral,
    ROUND(AVG(pp.avg_rate), 2)                                   AS media_premio,
    ROUND(CORR(bs.pct_covered, pp.avg_rate), 4)                  AS correlacao_cobertura_premio,
    ROUND(CORR(bs.avg_copay, pp.avg_rate), 4)                    AS correlacao_copay_premio
FROM benefit_score bs
JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = bs.plan_sk
JOIN plan_price pp    ON pp.plan_sk = bs.plan_sk AND pp.year_sk = bs.year_sk
WHERE dp.is_dental_only = FALSE
GROUP BY 1, 2, 3
ORDER BY bs.year_sk, dp.metal_level
```

```sql
-- Prêmio médio por categoria de benefício
SELECT
    dbc.benefit_category,
    fbc.year_sk                                                AS ano,
    COUNT(DISTINCT fbc.plan_sk)                               AS planos_com_categoria,
    ROUND(AVG(pp.avg_rate), 2)                                AS premio_medio_usd,
    ROUND(AVG(COALESCE(fbc.copay_inn_tier1, 0)), 2)          AS avg_copay,
    ROUND(AVG(COALESCE(fbc.coins_inn_tier1, 0)) * 100, 2)    AS avg_coinsurance_pct
FROM eedb015_gold.fct_benefit_coverage fbc
JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
JOIN (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
) pp ON pp.plan_sk = fbc.plan_sk AND pp.year_sk = fbc.year_sk
WHERE fbc.is_covered = TRUE
GROUP BY 1, 2
ORDER BY fbc.year_sk, premio_medio_usd DESC
```

---

### Q4 — Tamanho da Rede × Preço do Plano

```sql
-- Prêmio médio por porte de rede e estado
SELECT
    dn.business_year                                          AS ano,
    dn.state_code                                             AS estado,
    dn.network_size_tier                                      AS porte_rede,
    COUNT(DISTINCT dp.plan_sk)                               AS total_planos,
    ROUND(AVG(dn.plan_count), 1)                             AS media_planos_por_rede,
    ROUND(AVG(pp.avg_rate), 2)                               AS premio_medio_usd,
    ROUND(MIN(pp.avg_rate), 2)                               AS premio_min,
    ROUND(MAX(pp.avg_rate), 2)                               AS premio_max
FROM eedb015_gold.dim_network dn
JOIN eedb015_gold.dim_plan dp
    ON dp.network_id = dn.network_id
   AND dp.business_year = dn.business_year
   AND dp.state_code = dn.state_code
JOIN (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dn.business_year
WHERE dp.is_dental_only = FALSE
GROUP BY 1, 2, 3
ORDER BY dn.business_year, dn.state_code, dn.network_size_tier
```

```sql
-- Redes pequenas conseguem preços abaixo da média do estado?
WITH state_avg AS (
    SELECT geo_sk, year_sk, avg_premium_individual
    FROM eedb015_gold.fct_market_competition
),
network_premium AS (
    SELECT
        dp.state_code,
        dp.business_year,
        dn.network_size_tier,
        ROUND(AVG(pp.avg_rate), 2) AS avg_rate
    FROM eedb015_gold.dim_plan dp
    JOIN eedb015_gold.dim_network dn
        ON dn.network_id = dp.network_id AND dn.business_year = dp.business_year
    JOIN (
        SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
        FROM eedb015_gold.fct_plan_premium
        WHERE age = 27 AND tobacco_flag = 'No Preference'
        GROUP BY 1, 2
    ) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dp.business_year
    WHERE dp.is_dental_only = FALSE
    GROUP BY 1, 2, 3
)
SELECT
    np.state_code,
    np.business_year                                                   AS ano,
    np.network_size_tier                                              AS porte_rede,
    np.avg_rate                                                       AS premio_medio_rede,
    sa.avg_premium_individual                                         AS premio_medio_estado,
    ROUND(np.avg_rate - sa.avg_premium_individual, 2)                AS diferenca_vs_estado,
    ROUND((np.avg_rate / sa.avg_premium_individual - 1) * 100, 2)   AS variacao_pct
FROM network_premium np
JOIN state_avg sa
    ON sa.geo_sk = np.state_code AND sa.year_sk = np.business_year
ORDER BY np.business_year, np.state_code, np.network_size_tier
```

---

## Atividade 8 — Camada de Apresentação

### Ferramenta Sugerida

**Apache Superset** — open-source, custo zero, suporte nativo a Athena via SQLAlchemy, filtros cross-chart.
Alternativa: **Amazon QuickSight** (integração nativa AWS, sem infraestrutura adicional).

---

### Estrutura do Dashboard

#### Filtros Globais (todas as abas)

- `Ano`: 2014 / 2015 / 2016 (multi-select)
- `Estado`: dropdown com todos os estados
- `Nível Metálico`: Bronze / Silver / Gold / Platinum / Catastrophic
- `Tipo de Plano`: HMO / PPO / EPO / POS

---

#### Aba 1 — Visão Geral do Mercado

| Elemento | Tipo | Métrica |
|---|---|---|
| Total de Planos | KPI Card | `COUNT(DISTINCT plan_id)` |
| Seguradoras Ativas | KPI Card | `COUNT(DISTINCT issuer_id)` |
| Prêmio Médio (27 anos) | KPI Card | `AVG(avg_premium_individual)` |
| Prêmio por Estado | Mapa coroplético | `avg_premium_individual` |
| Evolução do Prêmio | Gráfico de linha | Prêmio médio por ano (multi-estado) |
| Ranking de Competição | Tabela | Estados por nível de competição × ano |

---

#### Aba 2 — Q1: Oncologia

| Elemento | Tipo | Métrica / Dimensões |
|---|---|---|
| Evolução Copay × Coinsurance | Gráfico de linha duplo eixo | `avg_copay_usd` e `avg_coinsurance_pct` por ano × benefício |
| Custo Total do Paciente | Barras agrupadas | Custo estimado anual por nível metálico × ano |
| Cobertura Oncológica por Estado | Heatmap | % planos com cobertura × estado × nível metálico |
| Melhor Nível Metálico | KPI Card | Nível com menor custo total estimado |

---

#### Aba 3 — Q2: Competição × Preço

| Elemento | Tipo | Métrica / Dimensões |
|---|---|---|
| Competição vs. Prêmio | Scatter plot | X: nº seguradoras; Y: prêmio médio (1 ponto/estado/ano) |
| Prêmio por Tier de Competição | Linha com banda | Prêmio médio por tier × ano |
| Maior Variação de Prêmio | Barras horizontais | Top 10 estados por variação % 2014→2016 |

---

#### Aba 4 — Q3: Benefícios × Preço

| Elemento | Tipo | Métrica / Dimensões |
|---|---|---|
| Prêmio por Categoria | Barras verticais | Prêmio médio por categoria × nível metálico |
| Cobertura vs. Prêmio | Scatter | X: % benefícios cobertos; Y: prêmio |
| Correlação por Tipo de Plano | Tabela com sparkline | Correlação cobertura-prêmio por PlanType × ano |

---

#### Aba 5 — Q4: Rede × Preço

| Elemento | Tipo | Métrica / Dimensões |
|---|---|---|
| Distribuição de Prêmios | Box plot | Por porte de rede (small / medium / large) |
| Premio vs. Média Estadual | Barras agrupadas | Desvio % vs. média do estado por porte × ano |
| Comparativo Estadual | Tabela | Diferença (USD e %) vs. média estadual por porte × estado × ano |

---

## Considerações Analíticas

### Insights Esperados

1. **Oncologia:** Platinum tende a ter menor exposição financeira total para pacientes crônicos, apesar do prêmio mais alto — o MOOP mais baixo compensa em tratamentos longos.
2. **Competição:** Estados com monopólio (1 seguradora) devem apresentar prêmios sistematicamente acima da média nacional.
3. **Benefícios × Preço:** Benefícios de especialidade (Specialty Drug, Infusion) têm correlação positiva significativa com o prêmio; preventivos têm correlação fraca (mandatórios em todos os planos ACA).
4. **Rede × Preço:** Redes pequenas (HMO restrito) devem apresentar prêmios até 15-20% menores, com MOOP potencialmente mais alto como contrapartida.

### Limitações dos Dados

- `network` tem ~3.800 linhas — `plan_count` é **proxy imperfeito** de amplitude real (não conta médicos/hospitais).
- `crosswalk` pode ter duplicatas (1 plano antigo → N novos), gerando fan-out em joins de linhagem.
- Dados de benefícios refletem **cobertura contratada**, não utilização real.
- Janela temporal de apenas 3 anos (2014-2016) limita o poder estatístico das tendências.

### Possível Evolução: Modelo Preditivo (Q3)

```
individualrate ~ MetalLevel + PlanType + statecode + businessyear
              + pct_covered_benefits + avg_copay_oncology
              + moop_individual + network_size_tier
              + num_active_issuers
```

Algoritmo sugerido: **Gradient Boosting (XGBoost/LightGBM)** com SHAP values para quantificar o peso de cada feature de benefício sobre o preço — responde diretamente à Q3.
