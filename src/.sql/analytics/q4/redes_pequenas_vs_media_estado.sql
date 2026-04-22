-- Q4 — Redes pequenas conseguem preços abaixo da média do estado?
WITH state_avg AS (
    SELECT geo_sk, year_sk, avg_premium_individual
    FROM eedb015_gold.fct_market_competition
),
network_premium AS (
    SELECT
        dp.state_code,
        dp.business_year,
        dn.network_size_tier,
        ROUND(AVG(pp.avg_rate), 2) AS avg_rate
    FROM eedb015_gold.dim_plan dp
    JOIN eedb015_gold.dim_network dn
        ON dn.network_id = dp.network_id AND dn.business_year = dp.business_year
    JOIN (
        SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
        FROM eedb015_gold.fct_plan_premium
        WHERE age = 27 AND tobacco_flag = 'No Preference'
        GROUP BY 1, 2
    ) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dp.business_year
    WHERE dp.is_dental_only = FALSE
    GROUP BY 1, 2, 3
)
SELECT
    np.state_code,
    np.business_year                                                   AS ano,
    np.network_size_tier                                              AS porte_rede,
    np.avg_rate                                                       AS premio_medio_rede,
    sa.avg_premium_individual                                         AS premio_medio_estado,
    ROUND(np.avg_rate - sa.avg_premium_individual, 2)                AS diferenca_vs_estado,
    ROUND((np.avg_rate / sa.avg_premium_individual - 1) * 100, 2)   AS variacao_pct
FROM network_premium np
JOIN state_avg sa
    ON sa.geo_sk = np.state_code AND sa.year_sk = np.business_year
ORDER BY np.business_year, np.state_code, np.network_size_tier
