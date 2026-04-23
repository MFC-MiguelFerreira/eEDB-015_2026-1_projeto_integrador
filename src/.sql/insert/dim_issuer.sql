INSERT INTO eedb015_gold.dim_issuer
SELECT
    pa.issuerid || '_' || CAST(pa.businessyear AS VARCHAR)    AS issuer_sk,
    pa.issuerid,
    pa.businessyear,
    pa.statecode                                              AS state_code,
    COUNT(DISTINCT SUBSTR(pa.planid, 1, 14))                  AS num_plans_offered,
    COUNT(DISTINCT pa.networkid)                              AS num_networks,
    CAST(ROUND(
        COUNT(DISTINCT SUBSTR(pa.planid, 1, 14)) * 1.0
        / NULLIF(COUNT(DISTINCT pa.networkid), 0)
    , 0) AS INT)                                              AS avg_network_size
FROM eedb015_silver.plan_attributes pa
WHERE SUBSTR(pa.planid, -2) = '00'
GROUP BY pa.issuerid, pa.businessyear, pa.statecode
