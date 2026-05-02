-- Q2 — Evolução YoY: variação do prêmio vs número de seguradoras por estado (2014 → 2015 → 2016)
-- LEFT JOIN de dim_geography garante os 51 estados no resultado mesmo sem dados de mercado.
SELECT
    dg.state_code,
    dg.state_name,
    dg.census_region                                                                    AS regiao,
    dg.census_division                                                                  AS divisao_censo,
    -- Seguradoras ativas por ano
    MAX(CASE WHEN mc.year_sk = 2014 THEN mc.num_active_issuers END)                    AS issuers_2014,
    MAX(CASE WHEN mc.year_sk = 2015 THEN mc.num_active_issuers END)                    AS issuers_2015,
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.num_active_issuers END)                    AS issuers_2016,
    -- Variação líquida de competição no período
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.num_active_issuers END)
        - MAX(CASE WHEN mc.year_sk = 2014 THEN mc.num_active_issuers END)              AS delta_issuers,
    -- Prêmio médio por ano (benchmark CMS 27 anos / sem tabaco, pré-computado na Gold)
    ROUND(MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END), 2)      AS premio_2014,
    ROUND(MAX(CASE WHEN mc.year_sk = 2015 THEN mc.avg_premium_individual END), 2)      AS premio_2015,
    ROUND(MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END), 2)      AS premio_2016,
    -- Variação total do período (2014 → 2016)
    ROUND(
        (MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END)
       - MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END))
        / NULLIF(MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END), 0) * 100,
        2
    )                                                                                    AS variacao_premio_pct_total,
    -- Variação 2014 → 2015
    ROUND(
        (MAX(CASE WHEN mc.year_sk = 2015 THEN mc.avg_premium_individual END)
       - MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END))
        / NULLIF(MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END), 0) * 100,
        2
    )                                                                                    AS variacao_premio_pct_14_15,
    -- Variação 2015 → 2016
    ROUND(
        (MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END)
       - MAX(CASE WHEN mc.year_sk = 2015 THEN mc.avg_premium_individual END))
        / NULLIF(MAX(CASE WHEN mc.year_sk = 2015 THEN mc.avg_premium_individual END), 0) * 100,
        2
    )                                                                                    AS variacao_premio_pct_15_16
FROM eedb015_gold.dim_geography                dg
LEFT JOIN eedb015_gold.fct_market_competition  mc ON mc.geo_sk = dg.geo_sk
GROUP BY dg.state_code, dg.state_name, dg.census_region, dg.census_division
ORDER BY variacao_premio_pct_total DESC NULLS LAST
