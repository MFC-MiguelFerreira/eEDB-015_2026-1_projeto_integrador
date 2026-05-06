-- Q4 — Redes pequenas conseguem preços abaixo da média do estado? (por nível metálico)
-- Corrige JOIN original: dn.state_code adicionado para evitar matches entre issuers distintos.
WITH state_avg AS (
    SELECT geo_sk, year_sk, avg_premium_individual
    FROM eedb015_gold.fct_market_competition
),
network_premium AS (
    SELECT
        dp.state_code,
        dp.business_year,
        dp.metal_level,
        dn.network_size_tier,
        ROUND(AVG(pp.avg_rate),          2)  AS avg_rate,
        ROUND(STDDEV_POP(pp.avg_rate),   2)  AS stddev_rate,
        COUNT(DISTINCT dp.plan_sk)           AS total_planos
    FROM eedb015_gold.dim_plan dp
    JOIN eedb015_gold.dim_network dn
        ON  dn.network_id    = dp.network_id
        AND dn.business_year = dp.business_year
        AND dn.state_code    = dp.state_code
    JOIN (
        SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_rate
        FROM eedb015_gold.fct_plan_premium
        WHERE age = 27 AND tobacco_flag = 'No Preference'
        GROUP BY 1, 2
    ) pp ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dp.business_year
    WHERE dp.is_dental_only  = FALSE
      AND dp.market_coverage = 'Individual'
    GROUP BY 1, 2, 3, 4
)
SELECT
    np.state_code,
    np.business_year                                                          AS ano,
    np.metal_level                                                            AS nivel_metalico,
    np.network_size_tier                                                      AS porte_rede,
    np.total_planos,
    np.avg_rate                                                               AS premio_medio_rede,
    np.stddev_rate                                                            AS desvio_padrao_rede,
    sa.avg_premium_individual                                                 AS premio_medio_estado,
    ROUND(np.avg_rate - sa.avg_premium_individual, 2)                        AS diferenca_vs_estado,
    ROUND(
        (np.avg_rate / NULLIF(sa.avg_premium_individual, 0) - 1) * 100, 2
    )                                                                          AS variacao_pct
FROM network_premium np
JOIN state_avg sa
    ON  sa.geo_sk  = np.state_code
    AND sa.year_sk = np.business_year
ORDER BY np.business_year, np.state_code, np.metal_level, np.network_size_tier
