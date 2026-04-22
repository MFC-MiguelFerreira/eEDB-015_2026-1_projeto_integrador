-- Q3 — Score de cobertura por plano vs prêmio: correlação por nível metálico
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
