# Guia de Analytics — Camada Gold

> Documentação das queries analíticas da camada Gold: o que cada uma responde, como argumentar com os resultados e como transformá-las em visualizações de BI efetivas.
> Para o catálogo de campos e o ER, consulte [../gold_catalog.md](../gold_catalog.md).

---

## Visão Geral

As oito queries estão distribuídas em quatro questões de negócio. Cada questão tem **uma query descritiva** (estrutura/distribuição) e **uma query analítica** (correlação/variação temporal). Nenhuma query usa JOIN com tabelas externas à camada Gold — elas são autossuficientes para consumo direto no PowerBI via conexão Athena.

| Questão | Query | Tipo de visual sugerido |
|---|---|---|
| Q1 | `evolucao_copay_coinsurance` | Linha/área + tabela de detalhamento |
| Q1 | `custo_total_paciente_cronico` | Barras agrupadas + KPI card |
| Q2 | `competicao_vs_premio_por_estado` | Scatter plot + mapa coroplético |
| Q2 | `evolucao_yoy_premio` | Scatter (delta issuers × delta prêmio) |
| Q3 | `correlacao_cobertura_premio` | Matriz de correlação + decomposição |
| Q3 | `premio_por_categoria_beneficio` | Barras horizontais rankeadas |
| Q4 | `premio_por_porte_rede` | Boxplot / barras por tier |
| Q4 | `redes_pequenas_vs_media_estado` | Waterfall / divergente por estado |

---

## Q1 — Estrutura de Custos em Tratamentos Oncológicos

**Questão:** Como evoluiu a relação entre Copay e Coinsurance para tratamentos de Câncer (Quimioterapia e Radioterapia) nos planos de 2014 a 2016? Qual categoria de plano minimiza a exposição financeira total do paciente com doenças crônicas que exigem terapia de infusão recorrente?

### `evolucao_copay_coinsurance.sql`

**O que responde:** Mostra, por ano e nível metálico, como se distribui a estrutura de custo (copay fixo vs. coinsurance percentual) nos três benefícios oncológicos — Chemotherapy, Radiation Therapy e Infusion Therapy — e qual é o deductible efetivo que o paciente precisa esgotar antes de a cobertura entrar em vigor.

**Como a query funciona:**

O JOIN triplo `fct_benefit_coverage × dim_plan × dim_benefit_category` filtra apenas benefícios com `is_oncology = TRUE` no mercado individual de planos não-odontológicos. Para cada combinação `(ano, metal_level, beneficio)` calcula:

- `pct_cobertura` — fração de planos que de fato cobre o benefício; revela se há erosão de cobertura ao longo dos anos
- `avg_copay_usd` — calculado apenas entre os planos com `is_covered = TRUE`, evitando diluir a média com planos que não cobrem
- `avg_coinsurance_pct` — multiplicado por 100 para ser exibido como percentual
- `avg_deductible_efetivo` — usa `is_subj_to_ded`: se `TRUE`, inclui o `deductible_individual` do plano no custo oculto; se `FALSE`, zero (custo começa na primeira sessão)

**Argumento analítico:**

O campo `avg_deductible_efetivo` é o elemento mais revelador desta query. Planos Bronze frequentemente apresentam `coinsurance` aparentemente razoável (ex.: 30%), mas com `is_subj_to_ded = TRUE` e `deductible_individual = $5.500`. Um paciente com câncer que inicia quimioterapia num plano Bronze paga os $5.500 de franquia inteiros antes de o plano contribuir com qualquer centavo. A query superficializa esse custo oculto em um único campo que justifica a comparação entre metal levels.

Planos Platinum, por outro lado, tendem a ter `deductible_individual ≈ 0` e `coinsurance_pct` mais baixo — o argumento visual é que o "custo visível" (coinsurance) e o "custo oculto" (deductible efetivo) colapsam juntos no nível Platinum, tornando-o o mais previsível para o paciente oncológico.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de linhas com `ano` no eixo X, `avg_coinsurance_pct` no eixo Y, `metal_level` como série, com slicer por `beneficio`. Isso mostra a trajetória de custo por metal level ao longo dos três anos.
- **Visual complementar:** gráfico de barras empilhadas com `avg_copay_usd` e `avg_deductible_efetivo` por `metal_level` — separa o custo explícito do custo oculto em uma única barra.
- **KPI card:** `pct_cobertura` para Chemotherapy em 2016 vs 2014 — evidencia se o mercado expandiu ou contraiu a cobertura oncológica.
- **Slicer recomendado:** `beneficio` (dropdown), `ano` (range slider).
- **Melhoria sugerida na query:** adicionar `dp.plan_type` (HMO/PPO/EPO) como coluna de saída sem agrupá-la. Isso permitiria no PowerBI criar um slicer de tipo de plano — PPOs historicamente têm coinsurance maior fora da rede, o que é relevante para pacientes oncológicos que buscam especialistas fora da rede.

---

### `custo_total_paciente_cronico.sql`

**O que responde:** Estima o custo financeiro total anual de um paciente crônico com câncer, combinando o custo de tratamento estimado (12 sessões/ano de quimioterapia ou infusão) com o prêmio anual, por nível metálico e ano.

**Como a query funciona:**

A CTE `oncology_cost` calcula o custo estimado por sessão usando a lógica:

```
COALESCE(copay_inn_tier1, coins_inn_tier1 × moop_individual, 0)
```

Quando o plano usa copay fixo: o custo por sessão é direto. Quando usa coinsurance: o custo por sessão é aproximado multiplicando a taxa de coassegurado pelo MOOP individual — o teto máximo de desembolso funciona como proxy do custo máximo de um tratamento completo. O `LEAST(custo_12_sessoes, moop_individual)` na saída é tecnicamente correto: o paciente nunca paga além do MOOP, independentemente de quantas sessões fizer.

A CTE `premium_27` usa o benchmark CMS (27 anos, sem preferência de tabaco) para capturar o custo do prêmio em condições padronizadas — evita que diferenças etárias entre estados contaminem a comparação de custo total.

**Argumento analítico:**

A métrica `custo_total_paciente_est` (`LEAST(custo_tratamento, MOOP) + prêmio_anual`) é o indicador de exposição financeira mais honesto disponível com os dados do dataset. Ela responde à questão com um número concreto: "quanto um paciente pagaria em um ano de tratamento, no pior caso".

O argumento central é que planos com `metal_level` mais alto têm prêmios maiores, mas o MOOP menor e o custo de tratamento menor — resultando em `custo_total` que pode ser *inferior* ao de planos Bronze, apesar do prêmio mais alto. Isso derruba a percepção popular de que planos baratos são sempre mais vantajosos para pacientes com doenças crônicas.

**Limitação crítica a declarar na apresentação:**

A estimativa de custo por sessão com coinsurance (`coins_inn_tier1 × moop_individual`) superestima o custo de sessões individuais quando o tratamento não chega a atingir o MOOP. O correto seria `coins_inn_tier1 × custo_real_quimioterapia`, mas o custo unitário de uma sessão não existe no dataset. O valor típico de uma sessão de quimioterapia no mercado americano varia de $3.000 a $15.000 dependendo do protocolo — use um benchmark fixo (ex: $10.000/sessão) na narrativa oral para contextualizar.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras agrupadas por `nivel_metalico`, com três barras por grupo: `custo_premio_anual`, `custo_tratamento_anual_est` e `custo_total_paciente_est`. O agrupamento lado a lado torna imediata a comparação entre o que é custo visível (prêmio) e custo de uso (tratamento).
- **Slicer:** `ano` — a evolução de 2014 para 2016 mostra se os planos ficaram mais ou menos acessíveis para pacientes crônicos.
- **KPI cards:** `moop_individual_medio` por `metal_level` — âncora da exposição máxima do paciente.
- **Melhoria sugerida na query:** parametrizar o número de sessões (atualmente hardcoded como 12) e o custo referência de sessão. No PowerBI, isso pode ser feito com um parâmetro "What-If" que permite ao usuário ajustar o número de sessões de 6 a 52 e ver o `custo_total` recalculado no visual — transforma a análise estática em uma ferramenta interativa de planejamento financeiro.
- **Melhoria adicional:** adicionar `dp.state_code` à query (via JOIN com `dim_geography`) para habilitar um mapa onde o usuário seleciona o estado e vê qual metal level é mais vantajoso localmente — dado que prêmios variam significativamente entre estados.

---

## Q2 — Competição e Precificação por Estado

**Questão:** Qual é a correlação entre a densidade de competição — medida pelo número de seguradoras operando num mesmo estado — e o valor médio do prêmio cobrado ao consumidor final?

### `competicao_vs_premio_por_estado.sql`

**O que responde:** Fornece, para cada estado e ano, o número de seguradoras ativas, a classificação de competição (`competition_tier`) e os prêmios médio e mediano — a base de dados para analisar se maior competição se correlaciona com prêmios menores.

**Como a query funciona:**

É uma query direta sobre `fct_market_competition` (já pré-computada na Gold) com JOIN em `dim_geography` para enriquecer com nome do estado e região do Censo. O resultado é intencialmente largo (todas as colunas disponíveis) para servir como dataset base de múltiplos visuais no PowerBI, sendo a filtragem feita no nível do BI.

**Argumento analítico:**

A inclusão simultânea de `premio_medio_usd` e `premio_mediano_usd` é deliberada. Em estados com poucos planos (monopoly/low), a média e a mediana convergem — há pouca dispersão. Em estados altamente competitivos com muitos planos, a média pode ser puxada para cima por planos Platinum de nicho, enquanto a mediana reflete o preço que a maioria dos consumidores de fato encontra. A divergência média-mediana é um indicador qualitativo da estrutura de mercado.

O campo `census_region` permite agrupar estados no PowerBI e evidenciar que os estados do `South` com mais seguradoras (TX, FL) não necessariamente têm prêmios mais baixos que estados do `Northeast` com menos competição — indicando que fatores estruturais (custo de vida, regulação estadual, mix de beneficiários) moderam o efeito de competição.

**Sugestões para BI (PowerBI):**

- **Visual principal:** scatter plot com `num_seguradoras` no eixo X, `premio_medio_usd` no eixo Y, `estado` como label de ponto, `census_region` como cor, `total_planos` como tamanho da bolha. Esse visual é o coração da argumentação da Q2 — mostra visualmente se a correlação negativa (mais issuers → menor prêmio) se sustenta.
- **Visual complementar:** mapa coroplético dos EUA com intensidade de cor em `premio_medio_usd`, slicer por `ano` — evidencia se os "desertos de cobertura" geográficos coincidem com prêmios altos.
- **KPI cards:** `competition_tier = 'monopoly'` — quantos estados estão nessa categoria em cada ano?
- **Slicer:** `ano` e `nivel_competicao` — permite filtrar apenas estados monopolísticos para uma análise focada.
- **Melhoria sugerida na query:** adicionar `num_counties_covered` via JOIN com `dim_geography` e `award_density = num_active_plans / num_counties_covered`. Estados com muitos planos concentrados em poucos condados (grandes cidades) têm uma "competição fictícia" que não atinge consumidores rurais — essa métrica contextualiza o efeito de competição geograficamente.

---

### `evolucao_yoy_premio.sql`

**O que responde:** Para cada estado, calcula a variação percentual do prêmio entre 2014 e 2016 e disponibiliza o número de issuers nos dois anos — base para correlacionar mudança de competição com variação de preço.

**Como a query funciona:**

Usa `MAX(CASE WHEN year_sk = YYYY THEN ...)` para pivotar os três anos em colunas, uma técnica necessária porque o Athena/Trino não tem `PIVOT` nativo. O `NULLIF` no denominador evita divisão por zero para estados sem dados em 2014. A ordenação por `variacao_premio_pct DESC` coloca os estados de maior inflação no topo — útil para identificar quais mercados se deterioraram mais.

**Argumento analítico:**

Esta query é a peça de evidência mais direta para a Q2. O argumento se constrói em dois passos:
1. Estados onde `issuers_2016 < issuers_2014` (issuers saíram do mercado) devem mostrar `variacao_premio_pct` maior — a saída de competidores remove pressão de preço.
2. Estados onde `issuers_2016 > issuers_2014` devem mostrar `variacao_premio_pct` menor ou até negativo.

Se esse padrão se confirmar nos dados, ele constitui evidência empírica da correlação pedida pela questão. Nos dados reais do marketplace 2014–2016, vários estados do centro-oeste tiveram saída de seguradoras e elevação acima da inflação geral, enquanto estados como NY e CA, com mercados mais estáveis, mantiveram variações mais moderadas.

**Sugestões para BI (PowerBI):**

- **Melhoria crítica na query:** a query compara apenas 2014 e 2016, pulando 2015. Adicione as colunas `issuers_2015` e `premio_2015` para habilitar um gráfico de linhas de 3 pontos — alguns estados tiveram pico em 2015 e correção em 2016, o que a comparação 2014→2016 mascara.
- **Melhoria adicional:** adicionar `delta_issuers = issuers_2016 - issuers_2014`. No PowerBI, isso permite um scatter plot com `delta_issuers` no eixo X e `variacao_premio_pct` no eixo Y — se a regressão linear desse scatter tiver inclinação negativa, a correlação está provada visualmente.
- **Visual principal sugerido:** scatter plot `delta_issuers × variacao_premio_pct`, com linha de tendência (disponível nativamente no PowerBI), colorido por `census_region`. Pontos no quadrante (+issuers, -prêmio) confirmam a hipótese; pontos no (+issuers, +prêmio) indicam mercados onde fatores externos dominaram.
- **Visual complementar:** tabela rankeada com os 10 estados de maior `variacao_premio_pct` e seus respectivos `delta_issuers` — dado que é naturalmente citado em apresentações ("o estado X teve 47% de aumento de prêmio e perdeu 3 seguradoras no período").

---

## Q3 — Benefícios como Variável de Precificação

**Questão:** Os benefícios fornecidos pelo plano são a única variável que influencia no valor final? É possível classificá-los e quantificar o peso de cada categoria sobre o preço do plano?

### `correlacao_cobertura_premio.sql`

**O que responde:** Calcula a correlação estatística (Pearson) entre a cobertura de benefícios (percentual de benefícios cobertos e copay médio) e o prêmio, segmentada por nível metálico, tipo de plano e ano.

**Como a query funciona:**

A CTE `benefit_score` agrega por plano a cobertura total: quantos benefícios o plano tem, quantos cobre, o percentual, e médias de copay e coinsurance (usando `COALESCE(..., 0)` para tratar planos sem cost-sharing como zero). A CTE `plan_price` usa o benchmark CMS (27 anos). O SELECT final usa `CORR(cobertura, prêmio)` — função Pearson nativa do Athena — para medir a força da associação dentro de cada célula `(metal_level, plan_type, ano)`.

**Argumento analítico:**

O coeficiente `correlacao_cobertura_premio` responde diretamente se cobertura de benefícios explica variação de prêmio. Um coeficiente alto (>0.6) dentro de um mesmo metal_level indicaria que planos que cobrem mais benefícios são mais caros — o que sustentaria a hipótese da questão. Um coeficiente baixo sugeriria que outros fatores (porte da rede, área geográfica, tipo de plano) têm mais peso.

O coeficiente `correlacao_copay_premio` é a contraparte: planos com copay mais alto tendem a ter prêmio mais alto (modelo copay) ou mais baixo (trade-off: prêmio mais barato em troca de maior custo no ponto de uso)? Se negativo, confirma o trade-off estrutural copay-prêmio comum no mercado americano.

A segmentação por `plan_type` é importante: HMOs e PPOs têm estruturas de benefícios distintas por design — mesclar os dois dilui a correlação real.

**Limitação a declarar:**

A query mede correlação de primeira ordem (linear, bivariada). O prêmio é determinado por múltiplas variáveis simultâneas (rede, geography, metal level, cobertura) — a correlação isolada não implica causalidade nem captura interações. O resultado é uma evidência descritiva, não causal.

**Sugestões para BI (PowerBI):**

- **Visual principal:** matriz de correlação — tabela de heat map com `metal_level` nas linhas, `plan_type` nas colunas e `correlacao_cobertura_premio` como valor com formatação condicional (verde para alta correlação positiva, vermelho para negativa). Esse visual comunica o resultado de forma imediata.
- **Slicer:** `ano` — permite mostrar se a correlação se fortaleceu ou enfraqueceu de 2014 a 2016, o que indica maturação do mercado.
- **KPI card:** `media_pct_cobertura` por `metal_level` — âncora de que Platinum cobre mais benefícios em média, contextualizando por que correlação é maior nesse tier.
- **Melhoria sugerida na query:** o `avg_copay_geral` usa `COALESCE(copay_inn_tier1, 0)`, o que conflate planos sem copay (estrutura coinsurance) com planos de copay zero. Adicione um campo separado `pct_plans_with_copay = SUM(CASE WHEN copay_inn_tier1 IS NOT NULL THEN 1 END) / COUNT(*)` — isso revela qual fração dos planos em cada tier usa copay vs. coinsurance, o que é um resultado descritivo valioso por si só.
- **Melhoria adicional:** incluir `dp.ehb_pct_premium` na saída (via JOIN com `dim_plan`). Esse campo mede diretamente qual fração do prêmio vai para cobrir EHBs — é a variável de precificação mais próxima da hipótese da Q3 e não está sendo explorada nas queries atuais.

---

### `premio_por_categoria_beneficio.sql`

**O que responde:** Para cada categoria de benefício (oncology, preventive, pharmacy, etc.), mostra o prêmio médio dos planos que cobrem aquela categoria, com médias de copay e coinsurance — ranking de quais categorias estão associadas a planos mais caros.

**Como a query funciona:**

O JOIN entre `fct_benefit_coverage` e `fct_plan_premium` é feito via `plan_sk + year_sk`. O filtro `is_covered = TRUE` garante que apenas planos que de fato cobrem a categoria são considerados. A subquery de `plan_price` agrega `avg_individual_rate` por plano (média de condados) antes do JOIN.

**Argumento analítico — e sua principal limitação:**

Esta query compara prêmios de planos que cobrem cada categoria. Como quase todos os planos cobrem benefícios básicos (primary_care, emergency), essas categorias terão amostras grandes e prêmios que refletem o mercado inteiro. Categorias mais especializadas (oncology, maternity) terão amostras menores e podem mostrar prêmios aparentemente mais altos simplesmente porque planos Platinum (mais caros) têm cobertura mais abrangente.

O argumento mais honesto não é "planos com cobertura oncológica são X% mais caros", mas sim: **dentro do mesmo `metal_level`, planos que cobrem categorias especializadas têm prêmio diferente dos que não cobrem?** A query atual não controla por metal_level nessa comparação.

**Sugestões para BI (PowerBI):**

- **Visual principal:** barras horizontais rankeadas com `benefit_category` no eixo Y e `premio_medio_usd` no eixo X, coloridas por `ano`. Mostra se o ranking de categorias por custo mudou entre 2014 e 2016.
- **Slicer:** `ano` (para comparação temporal).
- **Melhoria crítica na query:** adicionar `dp.metal_level` como dimensão de saída (sem agrupar por ela, mas disponível como slicer no BI). No PowerBI, o usuário poderia filtrar por `metal_level = 'Silver'` e ver quais categorias diferenciam planos Silver mais caros dos mais baratos — respondendo mais diretamente à questão.
- **Melhoria adicional:** adicionar `pct_planos_cobrindo = COUNT(DISTINCT fbc.plan_sk) / total_planos_no_ano` — a penetração da categoria no mercado. Categorias com alta penetração (>95%) são commodity; categorias com baixa penetração (<50%) são diferenciadoras de preço. Essa métrica transforma o gráfico de ranking simples em uma matriz `penetração × prêmio` muito mais argumentativa.

---

## Q4 — Tamanho da Rede e Preço do Plano

**Questão:** Qual é a relação entre a amplitude da rede de prestadores (Network Size) de uma seguradora e o preço final do plano? Seguradoras com redes menores conseguem oferecer preços significativamente mais baixos no mesmo estado?

### `premio_por_porte_rede.sql`

**O que responde:** Para cada combinação `(estado, ano, porte_rede)`, calcula o prêmio médio, mínimo e máximo dos planos — permite comparar a distribuição de preços por tier de rede dentro de um mesmo estado.

**Como a query funciona:**

O JOIN `dim_network × dim_plan` é feito por `network_id + business_year + state_code` — o state_code no JOIN é necessário porque `network_id` não é globalmente único (duas seguradoras em estados diferentes podem ter o mesmo código). A subquery de `plan_price` agrega o prêmio por plano antes do JOIN final.

**Argumento analítico:**

A pergunta da questão é direcional: redes menores → prêmios mais baixos? A query responde ao agregar `premio_medio_usd` por `porte_rede`. O campo `premio_min` e `premio_max` são igualmente importantes: se redes pequenas têm `premio_min` significativamente mais baixo que redes grandes, mas `premio_max` similar, indica que redes pequenas são uma *estratégia de nicho de preço*, não necessariamente mais baratas em todo o portfólio.

**Ressalva estrutural — declarar obrigatoriamente:**

`network_size_tier` é baseado em `plan_count` por rede, não em número real de prestadores credenciados (hospitais, médicos). O dataset não disponibiliza esse dado. Um plano HMO com rede de 3 produtos pode ter milhares de médicos credenciados, enquanto um plano PPO com rede de 25 produtos pode ter uma rede mais estreita por produto. A métrica é um proxy de *diversidade de portfólio*, não de *amplitude de rede* no sentido clínico. Isso deve ser declarado explicitamente no slide/relatório.

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras agrupadas por `porte_rede` (small/medium/large no eixo X), `premio_medio_usd` como barra, com barras de erro representando `premio_min` e `premio_max`. Slicer por `estado` e `ano`.
- **Slicer recomendado:** `estado` (para responder à pergunta dentro de um mercado específico, eliminando efeito geográfico) e `ano`.
- **Melhoria sugerida na query:** adicionar `dp.plan_type` como coluna de saída. HMOs por design têm redes mais restritas E prêmios mais baixos — sem controlar pelo tipo de plano, o efeito de `porte_rede` pode ser inteiramente explicado pela composição do tipo de plano no portfólio. No BI, o slicer `plan_type` permite ao usuário verificar se a relação porte-prêmio se sustenta mesmo dentro de HMOs ou só de PPOs.
- **Melhoria adicional:** incluir `dp.metal_level` — a relação rede × prêmio pode ser mediada pelo metal level (planos Gold tendem a ter redes maiores AND prêmios maiores, criando correlação espúria).

---

### `redes_pequenas_vs_media_estado.sql`

**O que responde:** Para cada estado e ano, calcula quanto o prêmio médio de cada porte de rede desvia (em USD e %) da média estadual geral — responde diretamente se redes pequenas conseguem praticar preços abaixo da média do mercado local.

**Como a query funciona:**

A CTE `state_avg` busca `avg_premium_individual` da `fct_market_competition` — que já usa o benchmark CMS (27 anos, sem tabaco). A CTE `network_premium` recalcula o prêmio médio por `(estado, ano, porte_rede)` usando a mesma subquery de `fct_plan_premium` com o mesmo benchmark. O JOIN final calcula `diferenca_vs_estado` (absoluta) e `variacao_pct` (relativa) — a métrica de resposta principal.

**Argumento analítico:**

Esta é a query mais diretamente argumentativa do projeto. Se `variacao_pct` para `porte_rede = 'small'` for consistentemente negativo (ex: -12% em média), significa que redes pequenas são sistematicamente mais baratas que a média estadual. Se positivo, a hipótese cai. A comparação das três linhas (`small`, `medium`, `large`) por estado permite visualizar se existe uma gradação monotônica (quanto menor a rede, menor o prêmio) ou se a relação é mais complexa.

O argumento se fortalece ao combinar com `competicao_vs_premio_por_estado.sql`: em estados com `competition_tier = 'monopoly'`, mesmo redes pequenas podem praticar prêmios acima da média de outros estados — a competição (Q2) modera o efeito de tamanho de rede (Q4).

**Sugestões para BI (PowerBI):**

- **Visual principal:** gráfico de barras divergentes com `porte_rede` nas linhas, `variacao_pct` nas colunas (valores negativos à esquerda, positivos à direita do zero). Slicer por `estado` e `ano`. Esse visual responde a pergunta "redes menores são mais baratas?" de forma imediata.
- **Visual complementar:** mapa dos EUA com intensidade colorida em `variacao_pct` para `porte_rede = 'small'` — mostra em quais estados redes pequenas são mais competitivas.
- **Melhoria sugerida na query:** adicionar `dp.metal_level` via JOIN com `dim_plan` antes da agregação por `porte_rede`. A pergunta-chave é: redes pequenas são mais baratas para todos os metal levels, ou apenas para Bronze? Planos Silver de rede pequena competindo em preço com Bronze de rede grande seria a evidência mais forte da questão.
- **Melhoria adicional:** adicionar `network_premium.avg_rate_std` (desvio padrão do prêmio dentro do tier). Redes pequenas com desvio padrão alto indicam que *alguns* planos são muito baratos mas outros não — a "vantagem de preço" não é uniforme. Essa nuance transforma a análise de "redes pequenas são X% mais baratas" para "redes pequenas têm maior dispersão de preço, concentrando os planos mais baratos do mercado".

---

## Mapa de Visualizações Cruzadas

As queries de diferentes questões se complementam nas seguintes combinações de BI:

| Combinação | Insight |
|---|---|
| Q2 `competicao_vs_premio` + Q4 `redes_pequenas_vs_media` | Verificar se em estados monopolistas (`competition_tier = 'monopoly'`), redes pequenas perdem sua vantagem de preço — responde se competição modera o efeito de tamanho de rede |
| Q1 `custo_total_cronico` + Q3 `correlacao_cobertura_premio` | Identificar se planos com maior score de cobertura oncológica têm MOOP menor — o custo de cobertura abrangente pode ser compensado pela limitação da exposição máxima |
| Q2 `evolucao_yoy_premio` + Q4 `premio_por_porte_rede` | Em estados onde o prêmio médio cresceu mais (alta `variacao_pct`), qual porte de rede absorveu mais o choque — redes pequenas mantiveram preço enquanto redes grandes aumentaram? |
| Q3 `premio_por_categoria` + Q1 `evolucao_copay_coinsurance` | Benefícios oncológicos são a categoria de maior `avg_coinsurance` — combinar com a evolução temporal evidencia se o mercado transferiu mais risco para o paciente ao longo de 3 anos |
