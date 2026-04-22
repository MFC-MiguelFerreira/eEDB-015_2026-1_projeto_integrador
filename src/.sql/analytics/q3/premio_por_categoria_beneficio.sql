-- Q3 — Prêmio médio por categoria de benefício
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
