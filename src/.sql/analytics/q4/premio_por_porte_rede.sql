-- Q4 — Prêmio médio por porte de rede, tipo de plano e nível metálico
-- JOIN com state_code previne matches cruzados: network_id não é globalmente único entre issuers.
SELECT
    dn.business_year                                                     AS ano,
    dp.state_code                                                        AS estado,
    dn.network_size_tier                                                 AS porte_rede,
    dp.plan_type                                                         AS tipo_plano,
    dp.metal_level                                                       AS nivel_metalico,
    COUNT(DISTINCT dp.plan_sk)                                          AS total_planos,
    COUNT(DISTINCT dn.network_id)                                       AS total_redes,
    ROUND(AVG(dn.plan_count),          1)                               AS media_planos_por_rede,
    ROUND(AVG(pp.avg_rate),            2)                               AS premio_medio_usd,
    ROUND(MIN(pp.avg_rate),            2)                               AS premio_min,
    ROUND(MAX(pp.avg_rate),            2)                               AS premio_max,
    ROUND(STDDEV_POP(pp.avg_rate),     2)                               AS premio_desvio_padrao
FROM eedb015_gold.dim_network dn
JOIN eedb015_gold.dim_plan dp
    ON  dp.network_id    = dn.network_id
    AND dp.business_year = dn.business_year
    AND dp.state_code    = dn.state_code
JOIN (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dn.business_year
WHERE dp.is_dental_only  = FALSE
  AND dp.market_coverage = 'Individual'
GROUP BY 1, 2, 3, 4, 5
ORDER BY ano, estado, porte_rede, tipo_plano, nivel_metalico
