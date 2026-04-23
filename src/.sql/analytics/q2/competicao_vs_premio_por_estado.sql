-- Q2 — Visão anual: número de seguradoras vs prêmio médio por estado
SELECT
    mc.year_sk                               AS ano,
    dg.state_code                            AS estado,
    dg.state_name,
    dg.census_region                         AS regiao,
    mc.num_active_issuers                    AS num_seguradoras,
    mc.competition_tier                      AS nivel_competicao,
    ROUND(mc.avg_premium_individual, 2)      AS premio_medio_usd,
    ROUND(mc.median_premium_individual, 2)   AS premio_mediano_usd,
    mc.num_active_plans                      AS total_planos
FROM eedb015_gold.fct_market_competition mc
JOIN eedb015_gold.dim_geography dg ON dg.geo_sk = mc.geo_sk
ORDER BY mc.year_sk, mc.num_active_issuers DESC
