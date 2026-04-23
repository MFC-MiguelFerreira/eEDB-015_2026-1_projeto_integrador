-- Q1 — Evolução anual de Copay × Coinsurance em tratamentos oncológicos por nível metálico
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
