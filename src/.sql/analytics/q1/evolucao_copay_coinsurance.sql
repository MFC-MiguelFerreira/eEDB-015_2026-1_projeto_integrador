-- Q1 — Evolução anual de Copay × Coinsurance em tratamentos oncológicos
--       por nível metálico e tipo de plano
SELECT
    fbc.year_sk                                                                        AS ano,
    dp.metal_level                                                                     AS nivel_metalico,
    dp.plan_type                                                                       AS tipo_plano,
    dbc.benefit_name                                                                   AS beneficio,
    COUNT(DISTINCT dp.plan_sk)                                                         AS total_planos,
    SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                                   AS planos_com_cobertura,
    ROUND(
        100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)
        / NULLIF(COUNT(DISTINCT dp.plan_sk), 0), 1
    )                                                                                   AS pct_cobertura,
    -- Copay e coinsurance calculados apenas sobre planos que de fato cobrem o benefício
    ROUND(AVG(CASE WHEN fbc.is_covered THEN fbc.copay_inn_tier1 END), 2)              AS avg_copay_usd,
    ROUND(AVG(CASE WHEN fbc.is_covered THEN fbc.coins_inn_tier1 END) * 100, 2)        AS avg_coinsurance_pct,
    -- % dos planos cobertos que exigem esgotamento do deductible antes do plano contribuir
    ROUND(
        100.0 * SUM(CASE WHEN fbc.is_covered AND fbc.is_subj_to_ded THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END), 0), 1
    )                                                                                   AS pct_subj_deductible,
    -- Deductible médio apenas dos planos cobertos onde o paciente precisa esgotá-lo primeiro
    ROUND(
        AVG(CASE WHEN fbc.is_covered AND fbc.is_subj_to_ded
                 THEN dp.deductible_individual END), 2
    )                                                                                   AS avg_deductible_efetivo,
    -- Limite médio de sessões anuais (NULL = sem limite contratual)
    ROUND(
        AVG(CASE WHEN fbc.is_covered AND fbc.limit_qty IS NOT NULL
                 THEN CAST(fbc.limit_qty AS DOUBLE) END), 1
    )                                                                                   AS avg_limite_sessoes
FROM eedb015_gold.fct_benefit_coverage  fbc
JOIN eedb015_gold.dim_plan              dp  ON dp.plan_sk    = fbc.plan_sk
JOIN eedb015_gold.dim_benefit_category  dbc ON dbc.benefit_sk = fbc.benefit_sk
WHERE dbc.is_oncology    = TRUE
  AND dp.is_dental_only  = FALSE
  AND dp.market_coverage = 'Individual'
  AND dp.metal_level     IN ('Bronze', 'Silver', 'Gold', 'Platinum')
GROUP BY 1, 2, 3, 4
ORDER BY beneficio, nivel_metalico, tipo_plano, ano
