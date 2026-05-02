# Guia de Analytics — Camada Gold

> Documentação das queries analíticas da camada Gold: o que cada uma responde, como argumentar com os resultados e como transformá-las em visualizações de BI efetivas.
> Para o catálogo de campos e o ER, consulte [../gold_catalog.md](../gold_catalog.md).

---

## Visão Geral

As dez queries estão distribuídas em quatro questões de negócio. Q1, Q2 e Q4 têm duas queries cada; Q3 tem quatro — duas analíticas e dois datasets de apoio. Nenhuma query usa JOIN com tabelas externas à camada Gold — elas são autossuficientes para consumo direto no PowerBI via conexão Athena.

| Questão | Query | Tipo de visual sugerido |
|---|---|---|
| Q1 | `evolucao_copay_coinsurance` | Linha/área + tabela de detalhamento |
| Q1 | `custo_total_paciente_cronico` | Barras agrupadas + KPI card |
| Q2 | `competicao_vs_premio_por_estado` | Scatter plot + mapa coroplético |
| Q2 | `evolucao_yoy_premio` | Scatter (delta issuers × delta prêmio) |
| Q3 | `correlacao_cobertura_premio` | Matriz heat map (metal_level × plan_type) |
| Q3 | `premio_por_categoria_beneficio` | Barras horizontais (delta_premio_pct por categoria) |
| Q3 | `faixa_cobertura_vs_premio` | Barras agrupadas (faixa cobertura × prêmio, cor = metal_level) |
| Q3 | `dataset_analitico_plano` | Scatter plot (pct_cobertura × preco, cor = metal_level) |
| Q4 | `premio_por_porte_rede` | Boxplot / barras por tier |
| Q4 | `redes_pequenas_vs_media_estado` | Waterfall / divergente por estado |

---

## Q1 — Estrutura de Custos em Tratamentos Oncológicos

**Questão:** Como evoluiu a relação entre Copay e Coinsurance para tratamentos de Câncer (Quimioterapia e Radioterapia) nos planos de 2014 a 2016? Qual categoria de plano minimiza a exposição financeira total do paciente com doenças crônicas que exigem terapia de infusão recorrente?

### `evolucao_copay_coinsurance.sql`

**O que responde:** Mostra, por ano, nível metálico e **tipo de plano** (HMO/PPO/EPO), como se distribui a estrutura de custo nos três benefícios oncológicos — Chemotherapy, Radiation Therapy e Infusion Therapy — e qual o deductible efetivo que o paciente precisa esgotar antes de a cobertura entrar em vigor.

**Como a query funciona:**

O JOIN triplo `fct_benefit_coverage × dim_plan × dim_benefit_category` filtra apenas benefícios com `is_oncology = TRUE` no mercado individual de planos não-odontológicos. Para cada combinação `(ano, metal_level, plan_type, beneficio)` calcula:

- `pct_cobertura` — `SUM(is_covered) / COUNT(DISTINCT plan_sk)`: denominador correto evita distorção por planos duplicados
- `avg_copay_usd` e `avg_coinsurance_pct` — calculados apenas sobre `is_covered = TRUE`, sem diluir a média com planos que não cobrem o benefício
- `pct_subj_deductible` — fração dos planos cobertos que exigem o esgotamento do deductible antes de o plano contribuir; campo ausente na versão anterior que revelava o custo oculto do Bronze
- `avg_deductible_efetivo` — corrigido para fazer AVG apenas sobre planos com `is_covered = TRUE AND is_subj_to_ded = TRUE`; a versão anterior incluía planos descobertos com valor 0, subestimando o deductible real
- `avg_limite_sessoes` — limite anual de sessões contratado; `NULL` indica sem limite; fundamental para terapias de infusão recorrentes

**Argumento analítico:**

A combinação `pct_subj_deductible` + `avg_deductible_efetivo` é o elemento mais revelador. Planos Bronze frequentemente apresentam `avg_coinsurance_pct` aparentemente razoável (ex.: 30%), mas com `pct_subj_deductible` próximo de 100% e `avg_deductible_efetivo = $5.500`. Um paciente que inicia quimioterapia num plano Bronze paga a franquia inteira antes do plano contribuir com qualquer centavo. Planos Platinum tendem a ter `pct_subj_deductible` próximo de zero — o custo visível e o custo oculto colapsam juntos no nível Platinum, tornando-o o mais previsível para o paciente oncológico.

O campo `tipo_plano` permite isolar um efeito importante: PPOs historicamente têm `coinsurance` maior **fora da rede**, o que é crítico para pacientes oncológicos que buscam especialistas específicos. HMOs de rede pequena podem ter `avg_limite_sessoes` mais restritivo para infusão — o que compromete tratamentos contínuos mesmo quando a coinsurance parece baixa.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de linhas com `ano` no eixo X, `avg_coinsurance_pct` no eixo Y, `metal_level` como série, slicer por `beneficio` e `tipo_plano`. Mostra a trajetória de custo por tier e filtra por tipo de rede.
- **Visual complementar:** gráfico de barras empilhadas com `avg_copay_usd` e `avg_deductible_efetivo` por `metal_level` — separa o custo explícito do custo oculto em uma única barra. A altura da barra de deductible em Bronze vs. Platinum conta a história em dois segundos.
- **Visual adicional:** gráfico de barras com `pct_subj_deductible` por `metal_level` — evidencia quantos planos cobertos ainda cobram deductible primeiro; útil para comunicar o "custo oculto" para audiências não técnicas.
- **KPI card:** `pct_cobertura` para Chemotherapy em 2016 vs. 2014 — evidencia se o mercado expandiu ou contraiu a cobertura oncológica no período.
- **Slicers recomendados:** `beneficio` (dropdown), `ano` (range slider), `tipo_plano` (multi-select).

---

### `custo_total_paciente_cronico.sql`

**O que responde:** Estima o custo financeiro total anual de um paciente crônico com câncer — combinando o custo de tratamento estimado (12 sessões/ano do benefício oncológico mais caro coberto pelo plano) com o prêmio anual, por nível metálico e ano.

**Como a query funciona:**

A CTE `oncology_cost` foi corrigida para produzir **uma linha por plano**: usa `MAX` sobre `estimated_session_cost` para capturar o pior caso quando o plano cobre tanto Chemotherapy quanto Infusion Therapy. A versão anterior produzia duas linhas por plano nesses casos, distorcendo a média do grupo. O filtro `market_coverage = 'Individual'` foi adicionado para excluir planos Small Group. A CTE também expõe `deductible_efetivo` (0 quando nenhum benefício coberto exige deductible prévio).

A lógica de estimação por sessão:
- Plano com copay fixo: custo por sessão = `copay_inn_tier1` (determinístico)
- Plano com coinsurance: custo por sessão = `coins_inn_tier1 × moop_individual` — o MOOP como proxy do custo máximo anual; esta é uma estimativa de pior caso (ver limitação abaixo)

O `LEAST(custo_12_sessoes, moop_individual)` é tecnicamente correto: o paciente nunca paga além do MOOP anual.

A CTE `premium_27` usa o benchmark CMS (27 anos, sem preferência de tabaco) para padronizar o custo do prêmio — evita que diferenças etárias entre estados contaminem a comparação.

**Campos-chave da saída:**

- `deductible_medio` — franquia média por tier: contextualiza o custo inicial antes de o plano contribuir
- `moop_individual_medio` — teto máximo de desembolso; junto com `custo_tratamento_anual_est`, mostra se o tratamento provavelmente esgota o MOOP
- `total_planos` — tamanho amostral por tier/ano

**Argumento analítico:**

A métrica `custo_total_paciente_est` (`LEAST(custo_tratamento, MOOP) + prêmio_anual`) é o indicador de exposição financeira mais honesto disponível. O argumento central: planos com `metal_level` mais alto têm prêmios maiores, mas MOOP menor e custo de tratamento menor — o `custo_total` de um plano Gold ou Platinum pode ser **inferior** ao de um plano Bronze, apesar do prêmio mensal mais alto. Isso derruba a percepção popular de que planos baratos são sempre mais vantajosos para pacientes com doenças crônicas.

**Limitação crítica a declarar na apresentação:**

A estimativa `coins_inn_tier1 × moop_individual` é um pior caso anual, não um custo por sessão. O correto seria `coins_inn_tier1 × custo_real_por_sessão`, mas esse dado não existe no dataset. Uma sessão de quimioterapia custa tipicamente $3.000–$15.000 nos EUA dependendo do protocolo. Para contextualizar na narrativa oral, assuma $10.000/sessão como benchmark de mercado.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras agrupadas por `nivel_metalico`, com três barras por grupo: `custo_premio_anual`, `custo_tratamento_anual_est` e `custo_total_paciente_est`. O agrupamento lado a lado torna imediata a comparação entre custo visível (prêmio) e custo de uso (tratamento).
- **Visual complementar:** gráfico de barras com `moop_individual_medio` e `deductible_medio` lado a lado por `metal_level` — âncoras da exposição financeira máxima.
- **KPI cards:** `custo_total_paciente_est` para Bronze vs. Platinum no ano mais recente — a diferença (ou ausência dela) é a mensagem central da Q1.
- **Slicer:** `ano` — a evolução 2014→2016 mostra se os planos ficaram mais ou menos acessíveis para pacientes crônicos.
- **Melhoria sugerida:** adicionar `dp.state_code` às CTEs e ao GROUP BY para habilitar um mapa onde o usuário seleciona o estado e vê qual metal level é mais vantajoso localmente — prêmios variam significativamente entre estados. A estrutura atual é nacional agregada.
- **Melhoria adicional:** parametrizar o número de sessões (hardcoded como 12) com um parâmetro "What-If" no PowerBI (range de 6 a 52 sessões) — transforma a análise estática em ferramenta interativa de planejamento financeiro para o paciente.

---

## Q2 — Competição e Precificação por Estado

**Questão:** Qual é a correlação entre a densidade de competição — medida pelo número de seguradoras operando num mesmo estado — e o valor médio do prêmio cobrado ao consumidor final?

### `competicao_vs_premio_por_estado.sql`

**O que responde:** Fornece, para cada estado e ano, o número de seguradoras ativas, a classificação de competição (`competition_tier`) e os prêmios médio e mediano. A versão atual **garante que todos os 51 estados aparecem em todos os anos**, mesmo aqueles sem dados federais de mercado.

**Como a query funciona:**

O padrão `CROSS JOIN dim_time × dim_geography + LEFT JOIN fct_market_competition` substitui o JOIN direto da versão anterior. Estados que operam exchanges próprios (CA, NY, CO, WA etc.) podem não ter dados na `fct_market_competition` federal — o padrão anterior os omitiria silenciosamente, distorcendo a visualização no mapa. Com o novo padrão, esses estados aparecem com `num_seguradoras = 0` e métricas de prêmio `NULL`, sinalizando explicitamente a ausência de dados.

Campos adicionados:
- `divisao_censo` — granularidade intermediária entre região e estado; útil para agrupar estados com mercados similares
- `condados_cobertos` — de `dim_geography.num_counties_covered`; proxy do alcance geográfico dos planos no estado
- `densidade_planos_por_condado` — `num_active_plans / num_counties_covered`; estados com muitos planos concentrados em poucos condados (metrópoles) têm "competição fictícia" que não atinge consumidores rurais

**Argumento analítico:**

A inclusão simultânea de `premio_medio_usd` e `premio_mediano_usd` é deliberada. Em estados com poucos planos (monopoly/low), média e mediana convergem — pouca dispersão. Em estados competitivos com muitos planos, a média pode ser puxada por planos Platinum de nicho, enquanto a mediana reflete o preço que a maioria dos consumidores encontra. A divergência média-mediana é um indicador qualitativo da estrutura de mercado.

`densidade_planos_por_condado` contextualiza o efeito de competição geograficamente: uma alta densidade no Texas pode estar concentrada em Austin/Houston/Dallas, enquanto o interior permanece com pouca cobertura.

**Sugestões para BI (PowerBI):**

- **Visual principal:** scatter plot com `num_seguradoras` no eixo X, `premio_medio_usd` no eixo Y, `estado` como label, `regiao` como cor, `total_planos` como tamanho da bolha. Este é o coração da argumentação da Q2.
- **Visual complementar:** mapa coroplético dos EUA com intensidade de cor em `premio_medio_usd`, slicer por `ano`. Estados com `num_seguradoras = 0` (sem dados federais) devem aparecer em cinza — o mapa comunica tanto o preço quanto a ausência de dados.
- **Visual adicional:** gráfico de barras com `densidade_planos_por_condado` por `regiao` — evidencia estados com competição nominal mas geograficamente concentrada.
- **KPI cards:** contagem de estados com `nivel_competicao = 'monopoly'` por ano — mostra se a concentração de mercado aumentou ou diminuiu no período.
- **Slicers:** `ano`, `nivel_competicao`, `regiao`.

---

### `evolucao_yoy_premio.sql`

**O que responde:** Para cada estado, calcula a variação percentual do prêmio em **três períodos** (2014→2015, 2015→2016 e 2014→2016) e o número de issuers nos três anos — base completa para correlacionar mudança de competição com variação de preço ao longo do tempo.

**Como a query funciona:**

Usa `MAX(CASE WHEN year_sk = YYYY THEN ...)` para pivotar os três anos em colunas (técnica necessária porque Athena/Trino não tem `PIVOT` nativo). O `LEFT JOIN` a partir de `dim_geography` garante que todos os 51 estados apareçam — estados sem dados terão NULLs em todos os campos de prêmio e issuers.

Campos adicionados vs. versão anterior:
- `issuers_2015` e `premio_2015` — dado que faltava e que permite analisar dinamismo do mercado em cada subperíodo
- `delta_issuers` — `issuers_2016 - issuers_2014`; negativo = perda de competição, positivo = ganho
- `variacao_premio_pct_14_15` e `variacao_premio_pct_15_16` — variações por subperíodo; revelam estados com pico em 2015 e correção em 2016 (padrão típico de ajuste actuarial)
- `divisao_censo` — permite agrupamentos geográficos mais finos no BI

**Argumento analítico:**

O argumento se constrói em dois passos com `delta_issuers × variacao_premio_pct_total`:
1. Estados com `delta_issuers < 0` (saída de competidores) devem mostrar `variacao_premio_pct_total` maior — a saída remove pressão de preço.
2. Estados com `delta_issuers > 0` devem mostrar `variacao_premio_pct_total` menor ou negativo.

A separação em subperíodos enriquece o argumento: alguns estados tiveram ajuste brusco em 2015 (seguradoras que subprecificaram em 2014) e estabilização em 2016. Comparar apenas 2014→2016 mascararia esse padrão de ajuste em dois tempos.

**Sugestões para BI (PowerBI):**

- **Visual principal:** scatter plot com `delta_issuers` no eixo X e `variacao_premio_pct_total` no eixo Y, colorido por `regiao`, com linha de tendência linear nativa do PowerBI. Pontos no quadrante (delta negativo, variação positiva) provam a hipótese; pontos fora dela indicam estados onde outros fatores dominaram.
- **Visual complementar:** gráfico de linhas com 3 pontos (2014, 2015, 2016) por estado — slicer por `estado` permite o usuário detalhar a trajetória individual. Os subperíodos mostram se a variação foi gradual ou em salto.
- **Visual adicional:** tabela rankeada com os 10 estados de maior `variacao_premio_pct_total` com colunas `delta_issuers`, `premio_2014`, `premio_2016` — dado que é naturalmente citado em apresentações.
- **Slicers recomendados:** `regiao`, `divisao_censo` — permite verificar se o padrão se sustenta por sub-região.

---

## Q3 — Benefícios como Variável de Precificação

**Questão:** Os benefícios fornecidos pelo plano são a única variável que influencia no valor final? É possível classificá-los e quantificar o peso de cada categoria sobre o preço do plano?

**Estrutura da resposta (4 queries):** A Q3 usa duas queries analíticas (`correlacao_cobertura_premio` e `premio_por_categoria_beneficio`) e dois datasets de apoio (`faixa_cobertura_vs_premio` e `dataset_analitico_plano`). A sequência argumentativa recomendada é: primeiro demonstrar que benefícios não são a única variável (scatter do dataset), depois quantificar o peso de cada categoria (delta cobre × não cobre), e por fim mostrar a correlação fraca dentro de células controladas.

---

### `correlacao_cobertura_premio.sql`

**O que responde:** Calcula correlações de Pearson entre cobertura de benefícios e prêmio, segmentadas por nível metálico, tipo de plano e ano. Inclui métricas de dispersão de preço dentro de cada célula para evidenciar que outros fatores além de benefícios explicam a variação.

**Como a query funciona:**

A CTE `benefit_score` agrega por plano: total de benefícios, quantos são cobertos, percentual, e estrutura de cost-sharing separando corretamente copay de coinsurance — sem `COALESCE(..., 0)`, que confundiria "plano sem copay" com "copay zero". A CTE `plan_price` usa o benchmark CMS (27 anos, sem preferência de tabaco). O SELECT final calcula três coeficientes de Pearson e métricas de dispersão de preço (stddev, min, max) dentro de cada célula `(metal_level, plan_type, ano)`.

**Campos-chave:**

- `desvio_padrao_premio` — argumento central: se alto dentro de uma célula (metal × plan_type), preços variam muito mesmo com cobertura similar, provando que outros fatores atuam
- `pct_beneficios_com_copay` — fração dos benefícios cobertos que usam copay fixo (vs. coinsurance); sem distorção por COALESCE
- `pct_premio_ehb_medio` — via `ehb_pct_premium` de `dim_plan`: fração do prêmio mandatada por lei; variável de precificação mais direta disponível
- `corr_ehb_pct_premio` — correlação entre EHB% e prêmio; tipicamente a mais alta das três correlações
- `corr_cobertura_premio` e `corr_num_beneficios_premio` — correlações de cobertura geral com prêmio; esperadas baixas (<0.4) quando controladas por metal_level

**Argumento analítico:**

O coeficiente `corr_cobertura_premio` baixo dentro de cada célula é evidência de que **benefícios não explicam sozinhos** a variação de preço. O `desvio_padrao_premio` alto dentro da mesma célula reforça: planos com cobertura similar têm preços muito diferentes — outros fatores (rede, estado, ehb_pct_premium) dominam.

O trade-off `corr_copay_premio` negativo confirma a lógica de mercado americano: prêmio e copay são compensatórios — planos com prêmio mais alto tendem a ter copay mais baixo, transferindo custo do ponto de uso para o prêmio mensal.

**Limitação a declarar:** Correlação de primeira ordem (linear, bivariada). O prêmio é determinado por múltiplas variáveis simultâneas — a correlação isolada é evidência descritiva, não causal.

**Sugestões para BI (PowerBI):**

- **Visual principal:** matriz heat map — `metal_level` nas linhas, `plan_type` nas colunas, `corr_cobertura_premio` como valor com formatação condicional (verde = correlação alta, vermelho = baixa/negativa). Slicer por `ano` mostra se a correlação se fortaleceu com a maturação do mercado.
- **Visual complementar:** gráfico de barras com `desvio_padrao_premio` por `metal_level` — visualmente demonstra que a dispersão de preço persiste independentemente de cobertura.
- **KPI card:** `pct_premio_ehb_medio` por `metal_level` — âncora de que o EHB% cresce de Bronze para Platinum, explicando parte do diferencial de preço sem relação com cobertura "extra".

---

### `premio_por_categoria_beneficio.sql`

**O que responde:** Para cada categoria de benefício e nível metálico, compara o prêmio médio dos planos que **cobrem** vs **não cobrem** aquela categoria. O `delta_premio_usd` e `delta_premio_pct` são o "peso financeiro" de cada categoria — controlados por metal_level para isolar o efeito da categoria do efeito do tier.

**Como a query funciona:**

A CTE `plan_category` agrega `fct_benefit_coverage` em uma linha por `(plan_sk, year_sk, benefit_category)` com flag `covers = 1/0` (MAX de `is_covered` na categoria). O JOIN com `dim_plan` e `plan_price` habilita a comparação direta de prêmios entre os dois grupos dentro do mesmo metal_level. O filtro `HAVING COUNT(DISTINCT plan_sk) >= 10` exclui combinações com amostra insuficiente.

**Campos-chave:**

- `pct_planos_cobrindo` — penetração da categoria no metal_level/ano: categorias com >95% são commodity (não diferenciam preço); <60% são diferenciadoras
- `premio_medio_cobre_usd` vs `premio_medio_nao_cobre_usd` — comparação direta dentro do mesmo tier
- `delta_premio_usd` e `delta_premio_pct` — o quanto a cobertura desta categoria está associada a prêmio mais alto; ranking direto de peso por categoria

**Argumento analítico:**

O argumento correto não é "planos com cobertura oncológica são X% mais caros" (correlação espúria com Platinum), mas sim: **dentro do mesmo `metal_level = 'Silver'`, planos Silver que cobrem oncology têm `delta_premio_pct` de Y% em relação aos Silver que não cobrem**. Esse delta isolado é o peso real da categoria.

Categorias com `pct_planos_cobrindo > 95%` e `delta_premio_pct ≈ 0` são **commodities regulatórias** (ex: emergency, primary_care) — todos os planos cobrem e o preço não diferencia. Categorias com baixa penetração e `delta_premio_pct` alto (ex: oncology, maternity em alguns estados) são **diferenciadoras de preço** — a matriz penetração × delta é o principal visual da Q3.

**Limitação a declarar:** O delta correlacional não implica causalidade — um `delta_premium_pct` positivo para oncology pode ser porque planos Platinum (já mais caros) cobrem mais categorias especializadas. A interpretação deve ser feita sempre dentro do mesmo `metal_level`, nunca cruzando tiers.

**Sugestões para BI (PowerBI):**

- **Visual principal:** barras horizontais rankeadas com `benefit_category` no eixo Y, `delta_premio_pct` no eixo X, slicer por `metal_level` e `ano`. Slicer por `metal_level = 'Silver'` é o mais argumentativo — Silver é o tier mais comparável entre planos.
- **Visual complementar:** scatter plot com `pct_planos_cobrindo` no eixo X e `delta_premio_pct` no eixo Y, uma bolha por categoria/tier — identifica visualmente quais categorias são commodity vs. diferenciadoras.
- **Slicer recomendado:** `metal_level` como filtro principal + `ano` para comparação temporal.

---

### `faixa_cobertura_vs_premio.sql`

**O que responde:** Dentro do mesmo nível metálico, planos com maior percentual de benefícios cobertos são mais caros? Agrupa planos em quatro faixas de cobertura e calcula prêmio médio, mediano e desvio padrão por faixa — revelando se a cobertura "bruta" de benefícios explica preço dentro de um mesmo tier.

**Como a query funciona:**

A CTE `benefit_score` calcula `pct_cobertura` por plano. O SELECT agrupa por `(metal_level, ano, faixa_cobertura)` — onde `faixa_cobertura` é um CASE bucketing `pct_cobertura` em `<70%`, `70-84%`, `85-94%`, `95-100%` — e calcula prêmio médio, mediano, desvio padrão e amplitude.

**Campos-chave:**

- `desvio_padrao_premio` dentro de cada faixa — argumento estrutural: se Silver com 90-95% de cobertura ainda tem stddev alto de prêmio, a cobertura bruta não determina o preço
- `premio_mediano_usd` — robusto a outliers de planos Platinum de nicho dentro da faixa
- `pct_premio_ehb_medio` — confirma se planos na faixa superior têm EHB% maior, explicando parte do diferencial de preço via mandato legal em vez de cobertura "extra"

**Argumento analítico:**

O visual responde diretamente: se os preços crescem monotonicamente de faixa 1 para faixa 4 dentro do mesmo metal_level, benefícios explicam preço. Se dentro da faixa `95-100%` o `desvio_padrao_premio` for grande (ex: $200+), planos com cobertura idêntica têm preços muito diferentes — provando que outros fatores dominam.

O resultado esperado nos dados reais: **dentro de um mesmo metal_level, a faixa de cobertura explica pouco da variação de preço** — o salto de preço real ocorre entre metal_levels, não entre faixas dentro do mesmo tier.

**Sugestões para BI (PowerBI):**

- **Visual principal:** barras agrupadas com `faixa_cobertura` no eixo X, `premio_medio_usd` no eixo Y, cor por `metal_level`. O agrupamento por cor visualmente demonstra que o salto de preço entre metal levels domina sobre a variação entre faixas de cobertura.
- **Visual complementar:** gráfico de barras de erro com `premio_medio_usd ± desvio_padrao_premio` por faixa — a largura das barras de erro dentro de cada faixa é o argumento visual para dispersão residual.
- **Slicer:** `ano` para mostrar se a relação cobertura-preço mudou de 2014 a 2016 (maturação do mercado tende a comprimir dispersão).

---

### `dataset_analitico_plano.sql`

**O que responde:** Dataset completo de uma linha por plano com preço, features estruturais (metal_level, plan_type, rede, estado) e score de cobertura de benefícios. Serve como base para scatter plots multivariados no PowerBI — o visual mais direto para demonstrar que benefícios não são a única variável de precificação.

**Como a query funciona:**

Três CTEs pré-agregam: `benefit_features` (score de cobertura + flags de categorias especiais via `dim_benefit_category`) e `plan_price` (prêmio benchmark por plano). O SELECT final une `dim_plan` + `dim_network` + as duas CTEs, produzindo uma linha por plano com ~30 colunas cobrindo variáveis estruturais, de rede, financeiras e de cobertura.

**Campos estruturais incluídos (variáveis não-benefício):**

- `nivel_metalico`, `tipo_plano` — classificação regulatória e de rede; as variáveis com maior poder explicativo de preço
- `porte_rede` e `planos_na_rede` — via `dim_network.network_size_tier`; proxy de amplitude de rede
- `pct_premio_ehb`, `moop_individual_usd`, `deductible_usd` — variáveis financeiras do plano
- `rede_nacional`, `tem_wellness`, `plano_novo` — features binárias de produto

**Campos de cobertura incluídos:**

- `pct_cobertura`, `beneficios_cobertos`, `copay_medio`, `coinsurance_medio_pct`
- Flags `tem_oncologia`, `tem_preventivo`, `tem_saude_mental`, `tem_cronico`
- Contagens por categoria: `qtd_farmacia`, `qtd_maternidade`, `qtd_emergencia`, `qtd_especialista`, `qtd_atencao_basica`, `qtd_oncologia`

**Argumento analítico:**

O scatter plot `pct_cobertura × preco_mensal_usd` com cor por `nivel_metalico` é o visual mais poderoso da Q3. Se os pontos formarem **clusters verticais de cor** (Bronze no fundo, Platinum no topo) sem alinhamento com o eixo X de cobertura, o argumento está provado visualmente: metal_level determina o nível de preço independentemente do percentual de benefícios cobertos.

Com slicers por `tipo_plano` e `porte_rede`, o usuário pode verificar se a relação muda para subgrupos específicos (ex: apenas HMOs, apenas redes pequenas).

**Limitação a declarar:** Dataset sem amostragem — inclui todos os planos individuais ativos com dados de prêmio disponíveis. Para análises de regressão fora do BI, exportar via CTAS para Parquet na Gold ou baixar via Athena JDBC.

**Sugestões para BI (PowerBI):**

- **Visual principal:** scatter plot com `pct_cobertura` no eixo X, `preco_mensal_usd` no eixo Y, `nivel_metalico` como cor, `tipo_plano` como forma (circle/square/diamond). Slicer por `ano` e `estado`. Esse é o visual-âncora da apresentação da Q3 — mostra clusters de cor sem correlação clara com o eixo X.
- **Visual complementar:** boxplot (usando visual de terceiros no PowerBI) de `preco_mensal_usd` por `nivel_metalico` com tooltip mostrando `pct_cobertura_medio` — evidencia que a amplitude de preço dentro de cada metal_level é grande e não explicada por cobertura.
- **Slicers recomendados:** `ano`, `estado`, `tipo_plano`, `porte_rede` — combinações permitem verificar se a relação benefício-preço muda em subgrupos específicos.
- **Uso avançado:** exportar o dataset como CSV via Athena e importar no PowerBI como tabela local para criar medidas DAX de correlação dinâmica (ex: `CORR(pct_cobertura, preco_mensal_usd)` filtrado pelo slicer de metal_level) — substitui a necessidade de reexecutar `correlacao_cobertura_premio.sql` para cada segmentação.

---

## Q4 — Tamanho da Rede e Preço do Plano

**Questão:** Qual é a relação entre a amplitude da rede de prestadores (Network Size) de uma seguradora e o preço final do plano? Seguradoras com redes menores conseguem oferecer preços significativamente mais baixos no mesmo estado?

### `premio_por_porte_rede.sql`

**O que responde:** Para cada combinação `(estado, ano, porte_rede, tipo_plano, metal_level)`, calcula o prêmio médio, mínimo, máximo e desvio padrão — permite comparar a distribuição de preços por tier de rede dentro do mesmo estado, controlando pelo tipo de plano e nível metálico.

**Como a query funciona:**

O JOIN `dim_network × dim_plan` é feito por `network_id + business_year + state_code` — o `state_code` no JOIN é obrigatório porque `network_id` não é globalmente único (dois issuers em estados diferentes podem ter o mesmo código). O filtro `market_coverage = 'Individual'` foi adicionado para excluir planos Small Group. A subquery de `plan_price` agrega o prêmio por plano antes do JOIN final usando o benchmark CMS padrão.

Campos adicionados vs. versão anterior:
- `tipo_plano` e `nivel_metalico` no GROUP BY — controles essenciais; sem eles, a relação porte-prêmio pode ser espúria (HMOs por design têm redes restritas E prêmios mais baixos; Platinum tem redes amplas E prêmios altos)
- `premio_desvio_padrao` — dispersão dentro do tier; redes pequenas com stddev alto indicam estratégia de nicho de preço, não uniformidade de desconto
- `total_redes` — quantas redes distintas compõem o tier no estado/ano

**Argumento analítico:**

A pergunta é direcional: redes menores → prêmios mais baixos? Com `tipo_plano` como controle, o argumento fica preciso: "dentro dos HMOs Silver de um estado, redes pequenas cobram X% a menos que redes grandes". Sem esse controle, a comparação confunde o tipo de rede com o tipo de plano.

O campo `premio_min` é igualmente importante: se redes pequenas têm `premio_min` significativamente mais baixo que redes grandes, mas `premio_max` similar, indica que redes pequenas são uma **estratégia de nicho de preço** (alguns planos muito baratos), não uma garantia de desconto generalizado. O `premio_desvio_padrao` alto confirma esse padrão.

**Ressalva estrutural — declarar obrigatoriamente:**

`network_size_tier` é baseado em `plan_count` por rede, não em número real de prestadores credenciados. O dataset não disponibiliza esse dado. Um HMO com 3 produtos pode ter milhares de médicos credenciados, enquanto um PPO com 25 produtos pode ter rede mais estreita por produto. A métrica é proxy de **diversidade de portfólio**, não de amplitude clínica da rede.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras agrupadas por `porte_rede` (small/medium/large), `premio_medio_usd` como barra, barras de erro com `premio_min`/`premio_max`. Slicers por `estado`, `tipo_plano` e `nivel_metalico`. A comparação dentro de `tipo_plano = 'HMO'` e `nivel_metalico = 'Silver'` é o corte mais limpo para a argumentação.
- **Visual complementar:** boxplot com `premio_desvio_padrao` por `porte_rede` — evidencia se redes pequenas têm maior dispersão de preço (estratégia de nicho) ou menor (produto padronizado).
- **Slicers recomendados:** `estado` (elimina efeito geográfico), `tipo_plano` (isola efeito de rede do efeito de produto), `nivel_metalico` (isola efeito de rede do efeito de tier), `ano`.

---

### `redes_pequenas_vs_media_estado.sql`

**O que responde:** Para cada estado, ano e **nível metálico**, calcula quanto o prêmio médio de cada porte de rede desvia (em USD e %) da média estadual geral — responde diretamente se redes pequenas praticam preços abaixo do mercado local, segmentado por tier.

**Como a query funciona:**

A CTE `state_avg` busca `avg_premium_individual` da `fct_market_competition` — benchmark CMS (27 anos, sem tabaco), pré-computado na Gold, representando a média do mercado estadual. A CTE `network_premium` recalcula o prêmio por `(estado, ano, metal_level, porte_rede)` com o mesmo benchmark.

Correções vs. versão anterior:
- **Bug corrigido:** o JOIN com `dim_network` agora inclui `AND dn.state_code = dp.state_code`. A versão anterior omitia esse critério — como `network_id` não é globalmente único, o JOIN poderia associar planos de um estado com redes de outro issuer em estado diferente, produzindo `avg_rate` incorreto
- `metal_level` adicionado ao GROUP BY — permite comparar "redes pequenas Bronze vs. média estadual" separado de "redes pequenas Platinum vs. média estadual"
- `stddev_rate` adicionado — dispersão dentro do tier/porte; redes pequenas com stddev alto têm vantagem de preço não uniforme
- `market_coverage = 'Individual'` adicionado para consistência com os demais filtros
- `NULLIF` adicionado no denominador de `variacao_pct` por segurança

**Argumento analítico:**

Esta é a query mais diretamente argumentativa do projeto. Se `variacao_pct` para `porte_rede = 'small'` for consistentemente negativo (ex: -12% em média), redes pequenas são sistematicamente mais baratas que a média estadual. A quebra por `metal_level` responde à pergunta mais precisa: **redes pequenas Bronze competem em preço com Bronze de redes grandes, ou apenas parecem mais baratas porque o mercado de rede pequena é composto principalmente por Bronze?**

Se `variacao_pct` para small/Bronze for negativo e para small/Silver for próximo de zero, a vantagem de preço das redes pequenas está concentrada no segmento básico — não é uma estratégia de toda a linha de produtos.

O `desvio_padrao_rede` nuança o argumento: redes pequenas com stddev alto concentram os **planos mais baratos do mercado**, mas também têm planos caros — a "vantagem de preço" não é uniforme. Isso transforma a narrativa de "redes pequenas são mais baratas" para "redes pequenas têm maior dispersão, concentrando as opções mais econômicas do mercado para quem pesquisa".

O argumento se fortalece ao cruzar com `competicao_vs_premio_por_estado.sql`: em estados monopolistas (`competition_tier = 'monopoly'`), mesmo redes pequenas podem praticar prêmios acima da média de outros estados — a competição (Q2) modera o efeito de tamanho de rede (Q4).

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras divergentes com `porte_rede` nas linhas e `variacao_pct` nas colunas (negativo à esquerda, positivo à direita do zero), slicer por `estado`, `ano` e `nivel_metalico`. Responde "redes menores são mais baratas?" de forma imediata.
- **Visual complementar:** mapa dos EUA com intensidade colorida em `variacao_pct` para `porte_rede = 'small'` e `nivel_metalico = 'Silver'` — o corte mais relevante; mostra em quais estados redes pequenas Silver são competitivas.
- **Visual adicional:** gráfico de dispersão `variacao_pct × desvio_padrao_rede` por `porte_rede` — quadrante (variacao negativa + stddev baixo) = redes pequenas uniformemente baratas; (variacao negativa + stddev alto) = redes pequenas com nicho de preço. Esse quadrante determina se a estratégia de rede pequena é confiável ou oportunista.
- **Slicers recomendados:** `estado`, `nivel_metalico`, `ano`.

---

## Mapa de Visualizações Cruzadas

As queries de diferentes questões se complementam nas seguintes combinações de BI:

| Combinação | Insight |
|---|---|
| Q2 `competicao_vs_premio` + Q4 `redes_pequenas_vs_media` | Em estados monopolistas (`competition_tier = 'monopoly'`), redes pequenas perdem a vantagem de preço — a competição (Q2) modera o efeito de tamanho de rede (Q4) |
| Q1 `custo_total_cronico` + Q3 `correlacao_cobertura_premio` | Planos com maior score de cobertura oncológica têm MOOP menor — o custo da cobertura abrangente pode ser compensado pela limitação da exposição máxima |
| Q2 `evolucao_yoy_premio` + Q4 `premio_por_porte_rede` | Em estados onde o prêmio médio cresceu mais (`variacao_pct_total` alto), qual porte de rede absorveu mais o choque — redes pequenas mantiveram preço enquanto redes grandes aumentaram? |
| Q3 `premio_por_categoria` + Q1 `evolucao_copay_coinsurance` | Benefícios oncológicos são a categoria de maior `avg_coinsurance` — combinar com a evolução temporal evidencia se o mercado transferiu mais risco para o paciente ao longo dos 3 anos |
| Q1 `evolucao_copay_coinsurance` (filtro `tipo_plano`) + Q4 `redes_pequenas_vs_media` | HMOs de redes pequenas têm `avg_limite_sessoes` mais restritivo para infusão — cruzar com o desconto de prêmio quantifica o trade-off entre custo e acesso para pacientes oncológicos |
