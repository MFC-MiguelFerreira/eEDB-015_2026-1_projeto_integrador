-- Q4 — Prêmio médio por porte de rede e estado
SELECT
    dn.business_year                                          AS ano,
    dn.state_code                                             AS estado,
    dn.network_size_tier                                      AS porte_rede,
    COUNT(DISTINCT dp.plan_sk)                               AS total_planos,
    ROUND(AVG(dn.plan_count), 1)                             AS media_planos_por_rede,
    ROUND(AVG(pp.avg_rate), 2)                               AS premio_medio_usd,
    ROUND(MIN(pp.avg_rate), 2)                               AS premio_min,
    ROUND(MAX(pp.avg_rate), 2)                               AS premio_max
FROM eedb015_gold.dim_network dn
JOIN eedb015_gold.dim_plan dp
    ON dp.network_id = dn.network_id
   AND dp.business_year = dn.business_year
   AND dp.state_code = dn.state_code
JOIN (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dn.business_year
WHERE dp.is_dental_only = FALSE
GROUP BY 1, 2, 3
ORDER BY dn.business_year, dn.state_code, dn.network_size_tier
