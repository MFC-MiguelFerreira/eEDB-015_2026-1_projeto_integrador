-- Q2 — Visão anual: número de seguradoras vs prêmio médio por estado
-- CROSS JOIN dim_geography × dim_time + LEFT JOIN garante que todos os 51 estados
-- aparecem para todos os anos, mesmo quando não há dados de mercado (exchanges estaduais).
SELECT
    dt.business_year                                                      AS ano,
    dg.state_code                                                         AS estado,
    dg.state_name,
    dg.census_region                                                      AS regiao,
    dg.census_division                                                    AS divisao_censo,
    dg.num_counties_covered                                               AS condados_cobertos,
    COALESCE(mc.num_active_issuers, 0)                                    AS num_seguradoras,
    COALESCE(mc.num_active_plans,   0)                                    AS total_planos,
    mc.competition_tier                                                   AS nivel_competicao,
    ROUND(mc.avg_premium_individual,    2)                                AS premio_medio_usd,
    ROUND(mc.median_premium_individual, 2)                                AS premio_mediano_usd,
    -- Proxy de dispersão geográfica da cobertura no estado
    ROUND(
        CAST(mc.num_active_plans AS DOUBLE)
        / NULLIF(dg.num_counties_covered, 0), 2
    )                                                                      AS densidade_planos_por_condado
FROM       eedb015_gold.dim_time                  dt
CROSS JOIN eedb015_gold.dim_geography             dg
LEFT  JOIN eedb015_gold.fct_market_competition    mc
        ON mc.geo_sk  = dg.geo_sk
       AND mc.year_sk = dt.business_year
ORDER BY dt.business_year, num_seguradoras DESC NULLS LAST
