-- Q2 — Evolução YoY: variação do prêmio vs número de seguradoras (2014 → 2016)
SELECT
    dg.state_code,
    dg.state_name,
    MAX(CASE WHEN mc.year_sk = 2014 THEN mc.num_active_issuers END)    AS issuers_2014,
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.num_active_issuers END)    AS issuers_2016,
    MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END) AS premio_2014,
    MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END) AS premio_2016,
    ROUND(
        (MAX(CASE WHEN mc.year_sk = 2016 THEN mc.avg_premium_individual END) -
         MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END))
        / NULLIF(MAX(CASE WHEN mc.year_sk = 2014 THEN mc.avg_premium_individual END), 0) * 100,
        2
    ) AS variacao_premio_pct
FROM eedb015_gold.fct_market_competition mc
JOIN eedb015_gold.dim_geography dg ON dg.geo_sk = mc.geo_sk
GROUP BY dg.state_code, dg.state_name
ORDER BY variacao_premio_pct DESC
