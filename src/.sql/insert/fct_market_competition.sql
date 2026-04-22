INSERT INTO eedb015_gold.fct_market_competition
SELECT
    r.statecode                                                  AS geo_sk,
    r.businessyear                                               AS year_sk,
    COUNT(DISTINCT pa.IssuerId)                                  AS num_active_issuers,
    COUNT(DISTINCT SUBSTR(pa.planid, 1, 14))                     AS num_active_plans,
    ROUND(AVG(CASE WHEN r.age = 27 AND r.tobacco = 'No Preference'
                   THEN r.individualrate END), 2)                AS avg_premium_individual,
    approx_percentile(CASE WHEN r.age = 27 AND r.tobacco = 'No Preference'
                           THEN r.individualrate END, 0.5)       AS median_premium_individual,
    CASE
        WHEN COUNT(DISTINCT pa.IssuerId) = 1 THEN 'monopoly'
        WHEN COUNT(DISTINCT pa.IssuerId) <= 3 THEN 'low'
        WHEN COUNT(DISTINCT pa.IssuerId) <= 6 THEN 'moderate'
        ELSE 'high'
    END AS competition_tier
FROM eedb015_silver.rate r
JOIN eedb015_silver.plan_attributes pa
    ON SUBSTR(pa.planid, 1, 14) = r.planid
   AND pa.businessyear = r.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14)
   AND br.businessyear = pa.businessyear
   AND br.dentalonlyplan = FALSE
   AND br.marketcoverage = 'Individual'
WHERE r.individualrate > 0 AND r.individualrate < 3000
  AND r.age BETWEEN 21 AND 64
GROUP BY r.statecode, r.businessyear
