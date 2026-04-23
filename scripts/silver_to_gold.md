# Camada Gold — Health Insurance Marketplace

> Documentação da camada Gold (Refined/Delivery) do Data Lake — eEDB-015/2026-1.
> **Tecnologia:** Amazon Athena · Iceberg · AWS Glue (Spark SQL)

---

## Estrutura do Repositório

```
src/.sql/
├── create/          # DDL — criação das tabelas Iceberg
├── insert/          # DML — carga Silver → Gold
└── analytics/       # Queries analíticas por questão de negócio
    ├── q1/          # Oncologia: Copay × Coinsurance
    ├── q2/          # Competição × Prêmio por estado
    ├── q3/          # Benefícios como variável de precificação
    └── q4/          # Tamanho da rede × Preço do plano
```

---

## Modelo Dimensional — Star Schema

Esquema estrela escolhido porque Athena/Trino performa melhor com joins de 1–2 níveis e as dimensões têm cardinalidade moderada.

### Diagrama de Relacionamentos

```
dim_time (3 linhas)
    │ 1
    │ N
fct_plan_premium ──N:1── dim_plan ──N:1── dim_issuer
    │                        │
    └──N:1── dim_geography   └──N:1── dim_network

fct_benefit_coverage ──N:1── dim_plan
                     └──N:1── dim_benefit_category
                     └──N:1── dim_time

fct_market_competition ──N:1── dim_geography
                        └──N:1── dim_time
```

---

## Tabelas de Fato

### `fct_plan_premium`

**Grão:** 1 linha por `(plan_id, business_year, state_code, age, tobacco_flag)`
**Fontes:** `rate` + `plan_attributes` + `business_rules`
**Volume estimado:** ~500 K linhas (redução de 12,7 M via agregação por faixa etária)

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` (FK) | STRING | → `dim_plan.plan_sk` |
| `geo_sk` (FK) | STRING | → `dim_geography.geo_sk` |
| `year_sk` (FK) | INT | → `dim_time.business_year` |
| `age` | INT | Idade em anos (21–64) |
| `tobacco_flag` | STRING | `'No Preference'` / `'Tobacco User/Non-Tobacco User'` |
| `avg_individual_rate` | DOUBLE | Prêmio médio mensal (USD) |
| `min_individual_rate` | DOUBLE | Prêmio mínimo no grupo |
| `max_individual_rate` | DOUBLE | Prêmio máximo no grupo |
| `rate_count` | BIGINT | Registros agregados |

DDL: [src/.sql/create/fct_plan_premium.sql](../src/.sql/create/fct_plan_premium.sql)
Carga: [src/.sql/insert/fct_plan_premium.sql](../src/.sql/insert/fct_plan_premium.sql)

---

### `fct_benefit_coverage`

**Grão:** 1 linha por `(plan_id, benefit_name, business_year)`
**Fontes:** `benefits_cost_sharing` + `plan_attributes`

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` (FK) | STRING | → `dim_plan.plan_sk` |
| `benefit_sk` (FK) | STRING | → `dim_benefit_category.benefit_sk` |
| `year_sk` (FK) | INT | → `dim_time.business_year` |
| `is_covered` | BOOLEAN | Plano cobre este benefício |
| `is_ehb` | BOOLEAN | É Essential Health Benefit |
| `copay_inn_tier1` | DOUBLE | Copagamento fixo em rede (USD) |
| `coins_inn_tier1` | DOUBLE | Coassegurado em rede (ex: 0.20 = 20%) |
| `copay_out_of_net` | DOUBLE | Copagamento fora da rede (USD) |
| `coins_out_of_net` | DOUBLE | Coassegurado fora da rede |
| `is_subj_to_ded` | BOOLEAN | Custo sujeito ao deductible primeiro |
| `limit_qty` | INT | Limite de sessões/visitas |
| `cost_type` | STRING | Derivado: `'copay'` / `'coinsurance'` / `'both'` / `'none'` |

> **Semântica de NULL em benefícios:** `copay_inn_tier1 IS NULL` indica que coinsurance se aplica; `coins_inn_tier1 IS NULL` indica que copay se aplica. Ambos NULL → `cost_type = 'none'`.

DDL: [src/.sql/create/fct_benefit_coverage.sql](../src/.sql/create/fct_benefit_coverage.sql)
Carga: [src/.sql/insert/fct_benefit_coverage.sql](../src/.sql/insert/fct_benefit_coverage.sql)

---

### `fct_market_competition`

**Grão:** 1 linha por `(state_code, business_year)`
**Fontes:** `rate` + `plan_attributes` + `business_rules`

| Campo | Tipo | Descrição |
|---|---|---|
| `geo_sk` (FK) | STRING | → `dim_geography.geo_sk` |
| `year_sk` (FK) | INT | → `dim_time.business_year` |
| `num_active_issuers` | BIGINT | Nº de seguradoras com planos ativos |
| `num_active_plans` | BIGINT | Total de planos disponíveis no estado |
| `avg_premium_individual` | DOUBLE | Prêmio médio (27 anos, `'No Preference'`) |
| `median_premium_individual` | DOUBLE | Prêmio mediano (p50) |
| `competition_tier` | STRING | `'monopoly'`(1) / `'low'`(2–3) / `'moderate'`(4–6) / `'high'`(7+) |

DDL: [src/.sql/create/fct_market_competition.sql](../src/.sql/create/fct_market_competition.sql)
Carga: [src/.sql/insert/fct_market_competition.sql](../src/.sql/insert/fct_market_competition.sql)

---

## Tabelas de Dimensão

### `dim_plan`

**PK:** `plan_sk = CONCAT(SUBSTR(planid, 1, 14), '_', business_year)`
**Fonte:** `plan_attributes` + `business_rules` + `crosswalk2015` + `crosswalk2016`

| Campo | Tipo | Descrição |
|---|---|---|
| `plan_sk` | STRING | Surrogate key |
| `plan_id_base` | STRING | HIOS Plan ID — 14 chars (sem sufixo) |
| `plan_id_full` | STRING | HIOS Plan ID — 17 chars (com variante) |
| `business_year` | INT | Ano (2014, 2015, 2016) |
| `plan_name` | STRING | Nome de marketing |
| `metal_level` | STRING | Bronze / Silver / Gold / Platinum / Catastrophic |
| `plan_type` | STRING | HMO / PPO / EPO / POS |
| `issuer_id` | STRING | ID da seguradora (5 dígitos HIOS) |
| `state_code` | STRING | Estado (2 chars) |
| `network_id` | STRING | ID da rede de prestadores |
| `service_area_id` | STRING | ID da área de serviço |
| `market_coverage` | STRING | Individual / Small Group |
| `is_dental_only` | BOOLEAN | Plano exclusivamente odontológico |
| `is_new_plan` | BOOLEAN | Plano sem histórico anterior |
| `wellness_program` | BOOLEAN | Oferece programa de bem-estar |
| `national_network` | BOOLEAN | Rede de cobertura nacional |
| `ehb_pct_premium` | DOUBLE | % do prêmio destinado a EHBs |
| `moop_individual` | DOUBLE | Teto máximo de desembolso anual — indivíduo (USD) |
| `deductible_individual` | DOUBLE | Franquia anual — indivíduo (USD) |
| `plan_lineage_id_2014` | STRING | PlanId equivalente em 2014 (via crosswalk; null se novo) |
| `plan_lineage_id_2015` | STRING | PlanId equivalente em 2015 |
| `plan_lineage_id_2016` | STRING | PlanId equivalente em 2016 |
| `network_plan_count` | INT | Planos que compartilham a mesma rede (proxy de tamanho) |

DDL: [src/.sql/create/dim_plan.sql](../src/.sql/create/dim_plan.sql)
Carga: [src/.sql/insert/dim_plan.sql](../src/.sql/insert/dim_plan.sql)

---

### `dim_geography`

**PK:** `geo_sk = state_code`
**Fonte:** seed estática (50 estados + DC) + `service_area` (contagem de condados)

> `state_name`, `census_region` e `census_division` não existem nas tabelas Silver — são hardcoded no INSERT via `VALUES`. Ver [src/.sql/insert/dim_geography.sql](../src/.sql/insert/dim_geography.sql).

| Campo | Tipo | Descrição |
|---|---|---|
| `geo_sk` | STRING | Chave primária (= `state_code`) |
| `state_code` | STRING | Sigla do estado (AK, AL, …) |
| `state_name` | STRING | Nome completo |
| `census_region` | STRING | Northeast / Midwest / South / West |
| `census_division` | STRING | Subdivisão do Censo |
| `num_counties_covered` | INT | Condados com cobertura registrada na Silver |

DDL: [src/.sql/create/dim_geography.sql](../src/.sql/create/dim_geography.sql)
Carga: [src/.sql/insert/dim_geography.sql](../src/.sql/insert/dim_geography.sql)

---

### `dim_benefit_category`

**PK:** `benefit_sk = to_hex(md5(to_utf8(benefit_name)))`
**Fonte:** `benefits_cost_sharing` (DISTINCT benefitname + categorização via CASE/LIKE)

| Campo | Tipo | Descrição |
|---|---|---|
| `benefit_sk` | STRING | Chave primária (hash MD5 do nome) |
| `benefit_name` | STRING | Nome original (ex: `'Chemotherapy'`) |
| `benefit_category` | STRING | Categoria analítica (ver tabela abaixo) |
| `is_oncology` | BOOLEAN | Benefício oncológico |
| `is_preventive` | BOOLEAN | Benefício preventivo |
| `is_mental_health` | BOOLEAN | Saúde mental |
| `is_chronic` | BOOLEAN | Tratamento crônico/recorrente |
| `is_ehb_standard` | BOOLEAN | EHB padrão pelo CMS |

**Mapeamento de categorias:**

| Categoria | Exemplos de `benefit_name` |
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

> **Nota MD5:** Em Athena/Trino, use `to_hex(md5(to_utf8(benefit_name)))`. Os arquivos INSERT já usam essa forma.

DDL: [src/.sql/create/dim_benefit_category.sql](../src/.sql/create/dim_benefit_category.sql)
Carga: [src/.sql/insert/dim_benefit_category.sql](../src/.sql/insert/dim_benefit_category.sql)

---

### `dim_issuer`

**PK:** `issuer_sk = issuer_id || '_' || business_year`
**Fonte:** `plan_attributes` (apenas variante base: `SUBSTR(planid, -2) = '00'`)

| Campo | Tipo | Descrição |
|---|---|---|
| `issuer_sk` | STRING | Surrogate key |
| `issuer_id` | STRING | ID único da seguradora (5 dígitos) |
| `business_year` | INT | Ano de referência |
| `state_code` | STRING | Estado principal de operação |
| `num_plans_offered` | INT | Total de planos oferecidos |
| `num_networks` | INT | Número de redes distintas |
| `avg_network_size` | INT | Média de planos por rede |

DDL: [src/.sql/create/dim_issuer.sql](../src/.sql/create/dim_issuer.sql)
Carga: [src/.sql/insert/dim_issuer.sql](../src/.sql/insert/dim_issuer.sql)

---

### `dim_network`

**PK:** `network_sk = network_id || '_' || business_year`
**Fonte:** `network` + `plan_attributes`

| Campo | Tipo | Descrição |
|---|---|---|
| `network_sk` | STRING | Surrogate key |
| `network_id` | STRING | ID da rede |
| `network_name` | STRING | Nome descritivo |
| `issuer_id` | STRING | Seguradora proprietária |
| `state_code` | STRING | Estado de operação |
| `business_year` | INT | Ano |
| `plan_count` | INT | Planos que usam esta rede |
| `network_size_tier` | STRING | `'small'` (1–5) / `'medium'` (6–20) / `'large'` (21+) |

DDL: [src/.sql/create/dim_network.sql](../src/.sql/create/dim_network.sql)
Carga: [src/.sql/insert/dim_network.sql](../src/.sql/insert/dim_network.sql)

---

### `dim_time`

**PK:** `business_year`
**Fonte:** seed estática (3 linhas hardcoded)

| Campo | Tipo | Descrição |
|---|---|---|
| `business_year` | INT | Ano fiscal (2014, 2015, 2016) |
| `year_label` | STRING | Rótulo para exibição |
| `aca_phase` | STRING | `'Year 1'` / `'Year 2'` / `'Year 3'` |

DDL: [src/.sql/create/dim_time.sql](../src/.sql/create/dim_time.sql)
Carga: [src/.sql/insert/dim_time.sql](../src/.sql/insert/dim_time.sql)

---

## Regras Críticas Silver → Gold

> Referência completa da Silver: [scripts/silver_exploration.md](silver_exploration.md)

### Incompatibilidade de `planid` entre tabelas

| Tabela | Formato | Tamanho |
|---|---|---|
| `rate`, `crosswalk2015`, `crosswalk2016` | Sem sufixo | 14 chars |
| `plan_attributes`, `benefits_cost_sharing`, `business_rules` | Com sufixo `-XX` | 17 chars |

```sql
-- rate → plan_attributes
ON SUBSTR(pa.planid, 1, 14) = r.planid AND pa.businessyear = r.businessyear

-- Filtro de variante base (evita duplicatas CSR)
WHERE pa.csrvariationtype LIKE 'Standard%'
-- equivalente: WHERE SUBSTR(pa.planid, -2) = '00'
```

### Filtros padrão aplicados em todos os fatos

```sql
WHERE r.individualrate > 0 AND r.individualrate < 3000   -- remove outliers
  AND r.age BETWEEN 21 AND 64                             -- exclui tarifas de família (age IS NULL ~4,7%)
  AND br.dentalonlyplan = FALSE
  AND br.marketcoverage = 'Individual'
```

### Benchmark de preço padrão CMS

Queries analíticas que comparam prêmio entre estados e planos usam o perfil CMS:

```sql
WHERE age = 27 AND tobacco_flag = 'No Preference'
```

> **Atenção:** `age` é INT na Silver — nunca use `age = '27'`. Os únicos valores de `tobacco` na Silver são `'No Preference'` (61,5%) e `'Tobacco User/Non-Tobacco User'` (38,5%).

---

## Particionamento Iceberg

| Tabela | Partição | Motivo |
|---|---|---|
| `fct_plan_premium` | `year_sk` | Queries filtram por ano |
| `fct_benefit_coverage` | `year_sk` | Idem |
| `fct_market_competition` | `year_sk` | Idem |
| `dim_plan` | `business_year` | Filtros por ano na dim principal |
| `dim_issuer` | `business_year` | Idem |
| `dim_network` | `business_year` | Idem |
| `dim_geography`, `dim_benefit_category`, `dim_time` | — | Tabelas pequenas, sem partição |

---

## Orquestração (AWS Step Functions — a implementar)

A carga das tabelas Gold deve seguir a ordem de dependência abaixo. A orquestração será implementada via AWS Step Functions com um Glue Job por tabela.

```
Fase 1 — Seeds (sem dependência)
    dim_time
    dim_geography
    dim_benefit_category

Fase 2 — Dimensões derivadas da Silver (paralelas entre si)
    dim_plan
    dim_issuer
    dim_network

Fase 3 — Tabelas de Fato (dependem de dim_plan)
    fct_plan_premium
    fct_benefit_coverage
    fct_market_competition
```

> Cada Glue Job executa o CREATE (idempotente via `IF NOT EXISTS`) seguido do INSERT correspondente.

---

## Queries Analíticas

As queries analíticas consomem a camada Gold e respondem às questões de negócio do projeto. Todas estão sob `src/.sql/analytics/`.

### Q1 — Estrutura de Custos em Oncologia

| Arquivo | Descrição |
|---|---|
| [src/.sql/analytics/q1/evolucao_copay_coinsurance.sql](../src/.sql/analytics/q1/evolucao_copay_coinsurance.sql) | Evolução anual de Copay × Coinsurance por nível metálico para Quimioterapia, Radioterapia e Infusão |
| [src/.sql/analytics/q1/custo_total_paciente_cronico.sql](../src/.sql/analytics/q1/custo_total_paciente_cronico.sql) | Estimativa do custo total anual (tratamento + prêmio) por nível metálico — identifica qual nível minimiza a exposição financeira |

### Q2 — Competição × Prêmio por Estado

| Arquivo | Descrição |
|---|---|
| [src/.sql/analytics/q2/competicao_vs_premio_por_estado.sql](../src/.sql/analytics/q2/competicao_vs_premio_por_estado.sql) | Número de seguradoras vs. prêmio médio por estado e ano |
| [src/.sql/analytics/q2/evolucao_yoy_premio.sql](../src/.sql/analytics/q2/evolucao_yoy_premio.sql) | Variação % do prêmio de 2014 → 2016 por estado |

### Q3 — Benefícios como Variável de Precificação

| Arquivo | Descrição |
|---|---|
| [src/.sql/analytics/q3/correlacao_cobertura_premio.sql](../src/.sql/analytics/q3/correlacao_cobertura_premio.sql) | Correlação entre % de benefícios cobertos e prêmio, segmentada por tipo e nível metálico |
| [src/.sql/analytics/q3/premio_por_categoria_beneficio.sql](../src/.sql/analytics/q3/premio_por_categoria_beneficio.sql) | Prêmio médio agrupado por categoria de benefício |

### Q4 — Tamanho da Rede × Preço do Plano

| Arquivo | Descrição |
|---|---|
| [src/.sql/analytics/q4/premio_por_porte_rede.sql](../src/.sql/analytics/q4/premio_por_porte_rede.sql) | Prêmio médio, mínimo e máximo por porte de rede (small/medium/large) e estado |
| [src/.sql/analytics/q4/redes_pequenas_vs_media_estado.sql](../src/.sql/analytics/q4/redes_pequenas_vs_media_estado.sql) | Diferença % entre prêmio de redes pequenas e a média do estado |
