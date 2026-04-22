INSERT INTO eedb015_gold.dim_plan
SELECT
    CONCAT(SUBSTR(pa.planid, 1, 14), '_', CAST(pa.businessyear AS VARCHAR)) AS plan_sk,
    SUBSTR(pa.planid, 1, 14)                                                 AS plan_id_base,
    pa.planid                                                                AS plan_id_full,
    pa.businessyear,
    pa.PlanMarketingName                                                     AS plan_name,
    pa.MetalLevel                                                            AS metal_level,
    pa.PlanType                                                              AS plan_type,
    pa.IssuerId                                                              AS issuer_id,
    pa.statecode                                                             AS state_code,
    pa.NetworkId                                                             AS network_id,
    pa.ServiceAreaId                                                         AS service_area_id,
    br.marketcoverage                                                        AS market_coverage,
    COALESCE(br.dentalonlyplan, FALSE)                                       AS is_dental_only,
    COALESCE(pa.IsNewPlan, FALSE)                                            AS is_new_plan,
    COALESCE(pa.WellnessProgramOffered, FALSE)                               AS wellness_program,
    CAST(COALESCE(pa.NationalNetwork, 0) AS BOOLEAN)                         AS national_network,
    pa.EHBPercentTotalPremium                                                AS ehb_pct_premium,
    pa.MEHBInnTier1IndividualMOOP                                            AS moop_individual,
    pa.MEHBDedInnTier1Individual                                             AS deductible_individual,
    c15.planid_2014                                                          AS plan_lineage_id_2014,
    c15.planid_2015                                                          AS plan_lineage_id_2015,
    c16.planid_2015_ref                                                      AS plan_lineage_id_2016,
    net_agg.plan_count                                                       AS network_plan_count
FROM eedb015_silver.plan_attributes pa
LEFT JOIN eedb015_silver.business_rules br
    ON br.standardcomponentid = SUBSTR(pa.planid, 1, 14) AND br.businessyear = pa.businessyear
LEFT JOIN (
    SELECT planid_2015, MAX(planid_2014) AS planid_2014
    FROM eedb015_silver.crosswalk2015
    GROUP BY planid_2015
) c15 ON c15.planid_2015 = SUBSTR(pa.planid, 1, 14) AND pa.businessyear = 2015
LEFT JOIN (
    SELECT planid_2016, MAX(planid_2015) AS planid_2015_ref
    FROM eedb015_silver.crosswalk2016
    GROUP BY planid_2016
) c16 ON c16.planid_2016 = SUBSTR(pa.planid, 1, 14) AND pa.businessyear = 2016
LEFT JOIN (
    SELECT NetworkId, businessyear, COUNT(DISTINCT planid) AS plan_count
    FROM eedb015_silver.plan_attributes
    GROUP BY NetworkId, businessyear
) net_agg ON net_agg.NetworkId = pa.NetworkId AND net_agg.businessyear = pa.businessyear
WHERE pa.csrvariationtype LIKE 'Standard%'
