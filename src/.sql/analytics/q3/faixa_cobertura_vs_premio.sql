-- Q3-C — Faixas de cobertura vs premio por nivel metalico
-- Responde: dentro do mesmo metal_level, planos com mais beneficios cobertos sao mais caros?
-- O desvio_padrao_premio dentro de cada celula (metal x faixa) e o argumento-chave:
-- se alto, preco varia muito mesmo com cobertura similar -> outros fatores tambem explicam preco.
-- Visual principal: barras agrupadas (faixa_cobertura no X, premio_medio no Y, cor = metal_level).
-- Visual complementar: grafico de barras de erro com desvio_padrao por faixa — evidencia dispersao.
WITH benefit_score AS (
    SELECT
        fbc.plan_sk,
        fbc.year_sk,
        ROUND(
            100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
            1
        )                                                                          AS pct_cobertura,
        SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                           AS beneficios_cobertos,
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.copay_inn_tier1 IS NOT NULL
                       THEN fbc.copay_inn_tier1 END), 2)                           AS copay_medio,
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.coins_inn_tier1 IS NOT NULL
                       THEN fbc.coins_inn_tier1 END) * 100, 2)                     AS coinsurance_medio_pct
    FROM eedb015_gold.fct_benefit_coverage fbc
    GROUP BY 1, 2
),
plan_price AS (
    SELECT plan_sk, year_sk, ROUND(AVG(avg_individual_rate), 2) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    dp.metal_level,
    bs.year_sk                                                                     AS ano,
    CASE
        WHEN bs.pct_cobertura >= 95 THEN '4 - 95-100%'
        WHEN bs.pct_cobertura >= 85 THEN '3 - 85-94%'
        WHEN bs.pct_cobertura >= 70 THEN '2 - 70-84%'
        ELSE                              '1 - abaixo 70%'
    END                                                                            AS faixa_cobertura,
    COUNT(*)                                                                       AS qtd_planos,
    ROUND(AVG(bs.pct_cobertura), 1)                                                AS pct_cobertura_media,
    ROUND(AVG(bs.beneficios_cobertos), 1)                                          AS media_beneficios_cobertos,
    ROUND(AVG(pp.avg_rate), 2)                                                     AS premio_medio_usd,
    ROUND(approx_percentile(pp.avg_rate, 0.5), 2)                                  AS premio_mediano_usd,
    -- Dispersao de preco dentro da faixa: argumento de que beneficios nao explicam tudo
    ROUND(STDDEV(pp.avg_rate), 2)                                                  AS desvio_padrao_premio,
    ROUND(MIN(pp.avg_rate), 2)                                                     AS premio_min_usd,
    ROUND(MAX(pp.avg_rate), 2)                                                     AS premio_max_usd,
    ROUND(AVG(bs.copay_medio), 2)                                                  AS copay_medio_usd,
    ROUND(AVG(bs.coinsurance_medio_pct), 2)                                        AS coinsurance_medio_pct,
    -- EHB% medio da faixa: correlaciona com pct_cobertura?
    ROUND(AVG(dp.ehb_pct_premium) * 100, 2)                                        AS pct_premio_ehb_medio
FROM benefit_score bs
JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = bs.plan_sk
JOIN plan_price pp             ON pp.plan_sk = bs.plan_sk AND pp.year_sk = bs.year_sk
WHERE dp.is_dental_only = FALSE
  AND dp.market_coverage = 'Individual'
GROUP BY
    dp.metal_level,
    bs.year_sk,
    CASE
        WHEN bs.pct_cobertura >= 95 THEN '4 - 95-100%'
        WHEN bs.pct_cobertura >= 85 THEN '3 - 85-94%'
        WHEN bs.pct_cobertura >= 70 THEN '2 - 70-84%'
        ELSE                              '1 - abaixo 70%'
    END
ORDER BY bs.year_sk, dp.metal_level, faixa_cobertura
