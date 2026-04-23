INSERT INTO eedb015_gold.fct_plan_premium
SELECT
    CONCAT(SUBSTR(pa.planid, 1, 14), '_', CAST(r.businessyear AS VARCHAR)) AS plan_sk,
    r.statecode                                                             AS geo_sk,
    r.businessyear                                                          AS year_sk,
    r.age,
    r.tobacco                                                               AS tobacco_flag,
    AVG(r.individualrate)                                                   AS avg_individual_rate,
    MIN(r.individualrate)                                                   AS min_individual_rate,
    MAX(r.individualrate)                                                   AS max_individual_rate,
    COUNT(*)                                                                AS rate_count
FROM eedb015_silver.rate r
JOIN eedb015_silver.plan_attributes pa
    ON SUBSTR(pa.planid, 1, 14) = r.planid
   AND pa.businessyear = r.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14)
   AND br.businessyear = pa.businessyear
WHERE r.individualrate > 0
  AND r.individualrate < 3000
  AND r.age BETWEEN 21 AND 64
  AND br.dentalonlyplan = FALSE
  AND br.marketcoverage = 'Individual'
GROUP BY 1, 2, 3, 4, 5
