-- Q3-B — Premio medio: planos que COBREM vs NAO COBREM cada categoria de beneficio
-- Argumento principal: delta_premio_usd e o "peso financeiro" de cada categoria,
-- controlado por metal_level para eliminar confusao com nivel de cobertura geral.
-- pct_planos_cobrindo revela se a categoria e commodity (>95%) ou diferenciador (<60%).
-- Visual principal: barras horizontais (benefit_category no Y, delta_premio_pct no X),
-- slicer por metal_level e ano — ranking de categorias por impacto de preco.
WITH plan_category AS (
    -- Uma linha por (plano, categoria): covers=1 se ao menos 1 beneficio da categoria e coberto
    SELECT
        fbc.plan_sk,
        fbc.year_sk,
        dbc.benefit_category,
        MAX(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)  AS covers
    FROM eedb015_gold.fct_benefit_coverage fbc
    JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
    GROUP BY 1, 2, 3
),
plan_price AS (
    SELECT plan_sk, year_sk, ROUND(AVG(avg_individual_rate), 2) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    pc.benefit_category,
    dp.metal_level,
    pc.year_sk                                                                     AS ano,
    COUNT(DISTINCT pc.plan_sk)                                                     AS total_planos,
    -- Penetracao: % dos planos no metal_level/ano que cobrem esta categoria
    ROUND(100.0 * SUM(pc.covers) / NULLIF(COUNT(*), 0), 1)                         AS pct_planos_cobrindo,
    -- Premio dos que COBREM
    ROUND(AVG(CASE WHEN pc.covers = 1 THEN pp.avg_rate END), 2)                    AS premio_medio_cobre_usd,
    -- Premio dos que NAO COBREM (mesmo metal_level — controle limpo)
    ROUND(AVG(CASE WHEN pc.covers = 0 THEN pp.avg_rate END), 2)                    AS premio_medio_nao_cobre_usd,
    -- Delta absoluto: cobrir esta categoria esta associado a preco X USD mais alto?
    ROUND(
        AVG(CASE WHEN pc.covers = 1 THEN pp.avg_rate END) -
        AVG(CASE WHEN pc.covers = 0 THEN pp.avg_rate END),
        2
    )                                                                              AS delta_premio_usd,
    -- Delta relativo: quanto % mais caro e o plano que cobre esta categoria?
    ROUND(
        (  AVG(CASE WHEN pc.covers = 1 THEN pp.avg_rate END)
         / NULLIF(AVG(CASE WHEN pc.covers = 0 THEN pp.avg_rate END), 0) - 1
        ) * 100,
        1
    )                                                                              AS delta_premio_pct
FROM plan_category pc
JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = pc.plan_sk
JOIN plan_price pp              ON pp.plan_sk = pc.plan_sk AND pp.year_sk = pc.year_sk
WHERE dp.is_dental_only = FALSE
  AND dp.market_coverage = 'Individual'
GROUP BY pc.benefit_category, dp.metal_level, pc.year_sk
HAVING COUNT(DISTINCT pc.plan_sk) >= 10
ORDER BY pc.year_sk, dp.metal_level, pct_planos_cobrindo DESC
