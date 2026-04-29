# Camada Gold — Decisões de Modelagem

> Documento técnico explicando o **porquê** de cada decisão na construção da camada Gold.
> Para o **o quê** (schemas, campos, DDL/DML), consulte [scripts/silver_to_gold.md](../../scripts/silver_to_gold.md).

---

## 1. Por Que Star Schema?

A camada Gold usa um esquema estrela clássico em vez de um modelo normalizado ou flat tables.

**Razão técnica:** O Athena/Trino performa melhor com joins de 1 nível (fato → dimensão) do que com joins encadeados. Em queries que filtram por `metal_level` ou `state_code`, o Athena consegue aplicar predicate pushdown direto na dimensão, eliminando partições inteiras do S3.

**Razão analítica:** Todas as questões do projeto (Q1–Q4) se enquadram no padrão "medir X agrupado por Y": prêmio por estado, cobertura de benefícios por plano, competição por ano. O star schema mapeia diretamente para esse padrão sem joins adicionais.

**Alternativa descartada:** Desnormalização total (uma única tabela wide). Rejeitada porque o cruzamento entre benefícios e prêmios exigiria duplicação massiva de dados — cada plano tem ~30 benefícios, multiplicar a tabela de prêmios por 30 seria inviável.

---

## 2. O Filtro `csrvariationtype LIKE 'Standard%'` — O Mais Importante

Este filtro aparece em quatro dos cinco INSERTs e é a decisão de modelagem mais crítica do projeto.

### O Que São as Variantes CSR?

Sob o Affordable Care Act, planos Silver são obrigados a oferecer variantes com **Cost-Sharing Reductions (CSR)** para beneficiários de baixa renda que recebem subsídio federal (APTC). Na tabela `plan_attributes`, cada plano base de 14 caracteres aparece até **6 vezes**, uma por variante:

| Sufixo (`planid[-2:]`) | `csrvariationtype`        | Para quem se aplica                                         |
|------------------------|---------------------------|-------------------------------------------------------------|
| `-00`                  | `Standard`                | Consumidor geral — **o plano real de mercado**              |
| `-04`                  | `CSR 73`                  | Renda entre 100–150% FPL (73% actuarial value)              |
| `-05`                  | `CSR 87`                  | Renda entre 150–200% FPL                                    |
| `-06`                  | `CSR 94`                  | Renda entre 200–250% FPL                                    |
| `-02`                  | `Zero Cost Sharing`        | Indígenas / Alaska Natives: sem copay, sem deductible       |
| `-03`                  | `Limited Cost Sharing`     | Indígenas / Alaska Natives: limites mais baixos             |

As variantes CSR têm **o mesmo prêmio** que a variante Standard — o subsídio de custo é pago pelo governo federal diretamente à seguradora, não pelo consumidor. Porém, têm **cost-sharing radicalmente diferente**: deductibles e copays artificialmente reduzidos.

### Por Que Filtrar?

Se incluíssemos todas as variantes:

1. **Inflação de contagem de planos:** Um estado com 100 planos Silver apareceria com até 600 "planos" — distorcendo `num_active_plans` na `fct_market_competition` e `network_plan_count` na `dim_plan`.

2. **Distorção de benefícios na Q1:** As variantes CSR 87 e CSR 94 zeram copays e deductibles para quimioterapia. Incluí-las na análise de "quanto custa tratamento oncológico" produziria uma falsa conclusão de que o mercado é mais barato do que é para a população geral.

3. **Duplicação sem valor analítico em prêmios:** Como prêmio não muda entre variantes, incluí-las multiplicaria as linhas da `fct_plan_premium` sem adicionar informação, apenas ruído.

4. **Join incorreto com `rate`:** A tabela `rate` usa IDs de 14 caracteres (sem sufixo). Um join sem filtro de variante geraria multiplicação cartesiana: 1 linha de rate × 6 linhas de plan_attributes = 6 linhas duplicadas na fato.

### Por Que `LIKE 'Standard%'` e Não `= '00'`?

O filtro `SUBSTR(pa.planid, -2) = '00'` e `pa.csrvariationtype LIKE 'Standard%'` são **funcionalmente equivalentes** para os dados deste dataset. Usamos o LIKE por ser mais legível e resiliente a variações de encoding do sufixo. Em `dim_issuer` e `dim_network` usamos `= '00'` pois lá não há o campo `csrvariationtype` no escopo do SELECT.

> **Exceção:** Planos de anos sem variantes CSR (alguns não-Silver de 2014) têm apenas o sufixo `-00`. O filtro `LIKE 'Standard%'` os captura corretamente sem precisar tratar casos especiais.

---

## 3. A Tabela `rate` e o Formato de `planid`

A tabela `rate` usa **14 caracteres** (`IssuerId[5] + PlanId[9]`), enquanto `plan_attributes` e `benefits_cost_sharing` usam **17 caracteres** (com sufixo `-XX`). Essa inconsistência é estrutural no dataset original.

```sql
-- Join correto entre rate e plan_attributes
ON SUBSTR(pa.planid, 1, 14) = r.planid
```

O `SUBSTR(pa.planid, 1, 14)` trunca o sufixo de variante, fazendo o join funcionar. Sem isso, **nenhuma linha seria retornada** — o join silenciosamente produziria zero registros, que é um dos bugs mais difíceis de detectar em pipelines de dados.

---

## 4. Filtros de Qualidade na `fct_plan_premium`

```sql
WHERE r.individualrate > 0 AND r.individualrate < 3000
  AND r.age BETWEEN 21 AND 64
  AND br.dentalonlyplan = FALSE
  AND br.marketcoverage = 'Individual'
```

**`individualrate > 0`:** A Silver contém registros com taxa zero que representam erros de submissão de seguradoras ao CMS. No ACA, nenhum plano de mercado individual tem prêmio zero — a lei exige pagamento mínimo.

**`individualrate < 3000`:** O ACA permite uma variação máxima de 3:1 entre a taxa do mais jovem e do mais velho (exceto tabaco). Para um adulto de 64 anos, o prêmio mais caro observado em estados de alto custo (Alaska, Wyoming) raramente ultrapassa $2.000. Valores acima de $3.000 indicam erros de submissão ou registros de categorias especiais (ex: COBRA) que não pertencem ao mercado individual.

**`age BETWEEN 21 AND 64`:** A tabela `rate` contém linhas para idades individuais (0–64) **e** para categorias compostas como `"Family"`, `"Couple"`, `"Primary Subscriber and One Dependent"`. Essas categorias de família não têm um `age` numérico ou têm `age IS NULL`. O filtro elimina essas categorias e foca no perfil adulto padrão do mercado individual, evitando dupla contagem (já que a taxa familiar é derivada das taxas individuais).

**`dentalonlyplan = FALSE`:** Planos exclusivamente dentários (`is_dental_only = TRUE`) são regulados de forma diferente sob o ACA — têm estrutura de benefícios, deductibles e prêmios incomparáveis com planos médicos. Incluí-los distorceria qualquer análise de prêmio médico.

**`marketcoverage = 'Individual'`:** O dataset inclui planos do mercado de **pequenas empresas (Small Group)**. Esse segmento tem dinâmica de preço diferente: as taxas são negociadas por grupo, não individualizadas por idade da mesma forma. Para as questões Q1–Q4, o foco é o consumidor individual.

---

## 5. Benchmark de Idade 27 — Padrão CMS

Na `fct_market_competition`, o prêmio médio e mediano são calculados com:

```sql
WHERE r.age = 27 AND r.tobacco = 'No Preference'
```

**Por que 27 anos?** O CMS usa o perfil de 27 anos como **referência de comparação entre planos** em todas as publicações oficiais de análise do Marketplace. A razão histórica é dupla:
1. É a idade-limite até a qual jovens adultos podem permanecer como dependentes no plano dos pais (ACA Seção 2714). Um consumidor de 27 anos está "entrando" no mercado individual pela primeira vez.
2. Está próximo do ponto médio da curva actuarial de risco no segmento jovem adulto — mais representativo do que as extremidades (21 ou 64 anos).

**Por que `'No Preference'` e não `'Tobacco User/Non-Tobacco User'`?** O ACA permite surcharge de até 50% para tabagistas. O perfil "No Preference" representa o **prêmio base sem surcharge**, que é o que o CMS usa para comparações padronizadas entre estados e seguradoras.

> Os únicos dois valores de `tobacco` na Silver são `'No Preference'` (61,5% das linhas) e `'Tobacco User/Non-Tobacco User'` (38,5%). Não há granularidade de "usuário" vs "não-usuário" — apenas se a preferência foi declarada.

---

## 6. Surrogate Keys — Estratégia por Tabela

| Dimensão | Surrogate Key | Estratégia | Motivo |
|---|---|---|---|
| `dim_plan` | `CONCAT(planid[14], '_', year)` | Composta natural | PlanId HIOS é único por ano; year evita colisão entre anos |
| `dim_issuer` | `issuerid \|\| '_' \|\| year` | Composta natural | IssuerId é reusado entre anos pela mesma seguradora |
| `dim_network` | `networkid \|\| '_' \|\| year` | Composta natural | NetworkId não é globalmente único entre issuers |
| `dim_geography` | `state_code` | Natural direta | 51 valores estáveis, nunca mudam |
| `dim_benefit_category` | `MD5(benefit_name)` | Hash determinístico | benefit_name é a única chave natural disponível; MD5 produz SK compacta e joinável sem lookup table |
| `dim_time` | `business_year` | Natural direta | 3 valores fixos |

**Por que MD5 em `dim_benefit_category`?** A tabela `benefits_cost_sharing` não tem um ID numérico para benefícios — o identificador natural é o nome textual (`benefitname`). Usar o nome diretamente como FK nas tabelas de fato seria caro (strings longas repetidas bilhões de vezes). O MD5 (`to_hex(md5(to_utf8(benefit_name)))`) produz uma string de 32 chars determinística e estável, que funciona como surrogate key sem a necessidade de uma sequência auto-incrementada.

---

## 7. `BOOL_OR(isehb)` em `dim_benefit_category`

```sql
BOOL_OR(isehb) AS is_ehb_standard
```

O campo `isehb` (Essential Health Benefit) em `benefits_cost_sharing` **varia por estado**. Cada estado define seu próprio benchmark de EHBs, aprovado pelo CMS. Um benefício como "Habilitation Services" é EHB em alguns estados e não em outros.

`BOOL_OR` agrega todos os estados e marca o benefício como EHB se ele for EHB em **qualquer** estado. É uma abordagem conservadora: prefere falsos positivos (marcar como EHB algo que só é EHB em um estado) a falsos negativos (marcar como não-EHB algo que é obrigatório em vários estados). Para análise de cobertura de mercado, esse comportamento é o correto.

---

## 8. Crosswalk — Linhagem de Planos

### O Problema

Entre 2014 e 2016, seguradoras frequentemente mudaram o HIOS Plan ID de seus planos por motivos regulatórios (fusões, resubmissões, mudanças de área de serviço). Sem o Crosswalk, **um mesmo produto de saúde aparece como planos "diferentes"** em cada ano, impossibilitando análise de inflação de prêmio longitudinal.

### Como Foi Implementado

```sql
-- Crosswalk 2015: mapeia planid_2015 → planid_2014
LEFT JOIN (
    SELECT planid_2015, MAX(planid_2014) AS planid_2014
    FROM eedb015_silver.crosswalk2015
    GROUP BY planid_2015
) c15 ON c15.planid_2015 = SUBSTR(pa.planid, 1, 14) AND pa.businessyear = 2015
```

**Por que `MAX(planid_2014)`?** O Crosswalk publicado pelo CMS pode ter mapeamentos M:1 — um plano de 2015 pode ser a consolidação de dois planos de 2014 (ex: fusão de seguradoras). A agregação com `MAX` escolhe deterministicamente um dos predecessores. Para análise de séries temporais de preço, isso é aceitável: o objetivo é rastrear a **trajetória de custo**, não auditar fusões societárias.

### Campos de Linhagem na `dim_plan`

Os três campos `plan_lineage_id_2014/2015/2016` permitem que queries analíticas cruzem planos equivalentes entre anos sem precisar conhecer os arquivos Crosswalk:

```sql
-- Exemplo: variação de prêmio de um plano entre 2014 e 2016
SELECT p16.plan_name, p16.plan_lineage_id_2014,
       pp14.avg_individual_rate AS premium_2014,
       pp16.avg_individual_rate AS premium_2016
FROM dim_plan p16
JOIN fct_plan_premium pp16 ON pp16.plan_sk = p16.plan_sk
JOIN dim_plan p14 ON p14.plan_id_base = p16.plan_lineage_id_2014
JOIN fct_plan_premium pp14 ON pp14.plan_sk = p14.plan_sk
WHERE p16.business_year = 2016 AND p14.business_year = 2014
  AND pp14.age = 27 AND pp16.age = 27
```

---

## 9. `moop_individual` e `deductible_individual` — Campos MEHB

Em `dim_plan`, os campos financeiros do plano usam especificamente:

```sql
pa.MEHBInnTier1IndividualMOOP      AS moop_individual,
pa.MEHBDedInnTier1Individual       AS deductible_individual,
```

**MEHB** = Medical + Essential Health Benefits (exclui dental e vision, que têm campos DEHB/VEHB separados).  
**InnTier1** = In-Network Tier 1, a rede primária/preferencial — o tier que quase todos os consumidores usam como referência de custo.  
**Individual** = nível individual, não familiar (o ACA tem deductibles e MOOPs separados por nível).

Escolher os campos MEHB/Tier1/Individual garante comparabilidade entre planos: todos têm esse tier, enquanto Tier 2 (redes complementares) ou campos "Combined" (médico + dental) existem apenas em alguns planos.

---

## 10. `network_plan_count` como Proxy de Tamanho de Rede

A tabela `network` do dataset original **não contém informação sobre o número de prestadores** — apenas metadados básicos da rede (nome, ID, issuer). O tamanho real de uma rede (número de médicos e hospitais credenciados) não está disponível publicamente no dataset.

O campo `network_plan_count` (contagem de planos que compartilham a mesma rede) é usado como **proxy de amplitude**. A lógica é: redes maiores tendem a ser compartilhadas por mais produtos de uma seguradora (HMO base + PPO + plano para pequenas empresas), enquanto redes menores são criadas especificamente para um único produto de baixo custo.

> Essa limitação deve ser explicitada na análise Q4: a correlação é entre **número de planos por rede** e prêmio — não entre número de prestadores e prêmio. A interpretação é indireta.

---

## 11. `approx_percentile` para Mediana

```sql
approx_percentile(CASE WHEN r.age = 27 ... THEN r.individualrate END, 0.5)
    AS median_premium_individual
```

O Athena/Trino não tem função `MEDIAN()` nativa. `approx_percentile(x, 0.5)` calcula o percentil 50 usando o algoritmo **Quantile Digest (Q-Digest)**, com erro relativo garantido de ~1%. Para distribuições de prêmio com dezenas de milhares de observações por estado/ano, esse erro é irrelevante na prática.

A mediana é importante para a Q2 porque distribuições de prêmio são **fortemente enviesadas à direita** (planos de alto custo com poucos beneficiários inflam a média). A mediana representa melhor o "prêmio típico" que um consumidor mediano enfrenta.

---

## 12. `competition_tier` — Classificação de Competição

```sql
CASE
    WHEN COUNT(DISTINCT pa.IssuerId) = 1 THEN 'monopoly'
    WHEN COUNT(DISTINCT pa.IssuerId) <= 3 THEN 'low'
    WHEN COUNT(DISTINCT pa.IssuerId) <= 6 THEN 'moderate'
    ELSE 'high'
FROM fct_market_competition
```

Os limiares (1 / 2–3 / 4–6 / 7+) foram definidos com base em benchmarks de literatura de economia de saúde. Estudos do Kaiser Family Foundation e do NBER sobre mercados ACA encontraram que:

- **1 seguradora (monopoly):** Prêmios tipicamente 20–40% acima da média nacional — sem pressão competitiva.
- **2–3 seguradoras (low):** Mercado oligopolístico; precificação coordenada é comum em estados rurais.
- **4–6 seguradoras (moderate):** Competição real começa a comprimir margens.
- **7+ seguradoras (high):** Mercados competitivos — típico de grandes centros urbanos (CA, NY, TX).

> No período 2014–2016, ~30% dos condados dos EUA tinham apenas 1 seguradora disponível no marketplace.

---

## 13. Por Que Iceberg em Vez de Hive Tables?

Todas as tabelas usam `TBLPROPERTIES ('table_type'='iceberg')`.

**Idempotência dos INSERTs:** O Glue Job executa `CREATE IF NOT EXISTS` + `INSERT`. Com tabelas Hive, reexecutar o job duplicaria os dados. Com Iceberg, é possível usar `INSERT OVERWRITE` ou deletar snapshots — e o pipeline pode ser re-executado com segurança.

**Partition pruning correto:** Tabelas Hive particionadas no Athena exigem `MSCK REPAIR TABLE` ou `ALTER TABLE ADD PARTITION` após inserção. Iceberg atualiza o manifesto de partições automaticamente — crítico quando o Glue Job é orquestrado pelo Step Functions e não há intervenção manual.

**Time travel:** Iceberg mantém histórico de snapshots. Se um INSERT introduzir dados incorretos, é possível fazer rollback para o snapshot anterior sem reprocessar toda a Silver.

---

## 14. Ordem de Carga e Dependências

```
Fase 1 — Seeds (sem dependência Silver):
    dim_time              ← 3 linhas hardcoded
    dim_geography         ← 51 linhas hardcoded + count de condados da Silver
    dim_benefit_category  ← DISTINCT de benefits_cost_sharing

Fase 2 — Dimensões derivadas (paralelas entre si):
    dim_plan      ← plan_attributes + business_rules + crosswalk2015/2016
    dim_issuer    ← plan_attributes
    dim_network   ← network + plan_attributes

Fase 3 — Fatos (dependem de dim_plan estar carregada):
    fct_plan_premium       ← rate + plan_attributes + business_rules
    fct_benefit_coverage   ← benefits_cost_sharing + plan_attributes
    fct_market_competition ← rate + plan_attributes + business_rules
```

As tabelas de fato **não fazem JOIN com as dimensões Gold** — elas lêem diretamente da Silver e geram as FKs calculando o mesmo `plan_sk` que a `dim_plan` usa. Isso evita dependência de carga sequencial entre fato e dimensão, simplificando a orquestração no Step Functions.
