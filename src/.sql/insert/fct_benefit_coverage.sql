INSERT INTO eedb015_gold.fct_benefit_coverage
SELECT
    CONCAT(SUBSTR(bcs.planid, 1, 14), '_', CAST(bcs.businessyear AS VARCHAR))    AS plan_sk,
    to_hex(md5(to_utf8(bcs.benefitname)))                                        AS benefit_sk,
    bcs.businessyear                                                             AS year_sk,
    bcs.iscovered,
    bcs.isehb,
    bcs.copayinntier1                                                            AS copay_inn_tier1,
    bcs.coinsinntier1                                                            AS coins_inn_tier1,
    bcs.copayoutofnet                                                            AS copay_out_of_net,
    bcs.coinsoutofnet                                                            AS coins_out_of_net,
    bcs.issubjtodedtier1                                                         AS is_subj_to_ded,
    bcs.limitqty                                                                 AS limit_qty,
    CASE
        WHEN bcs.copayinntier1 IS NOT NULL AND bcs.coinsinntier1 IS NOT NULL THEN 'both'
        WHEN bcs.copayinntier1 IS NOT NULL THEN 'copay'
        WHEN bcs.coinsinntier1 IS NOT NULL THEN 'coinsurance'
        ELSE 'none'
    END AS cost_type
FROM eedb015_silver.benefits_cost_sharing bcs
JOIN eedb015_silver.plan_attributes pa
    ON pa.planid = bcs.planid
   AND pa.businessyear = bcs.businessyear
   AND pa.csrvariationtype LIKE 'Standard%'
