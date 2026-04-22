INSERT INTO eedb015_gold.dim_network
WITH net_plan_count AS (
    SELECT networkid, businessyear, COUNT(DISTINCT SUBSTR(planid, 1, 14)) AS plan_count
    FROM eedb015_silver.plan_attributes
    WHERE SUBSTR(planid, -2) = '00'
    GROUP BY networkid, businessyear
)
SELECT
    n.networkid || '_' || CAST(n.businessyear AS VARCHAR)      AS network_sk,
    n.networkid,
    n.networkname                                              AS network_name,
    n.issuerid                                                 AS issuer_id,
    n.statecode                                                AS state_code,
    n.businessyear,
    COALESCE(npc.plan_count, 0)                                AS plan_count,
    CASE
        WHEN COALESCE(npc.plan_count, 0) <= 5  THEN 'small'
        WHEN COALESCE(npc.plan_count, 0) <= 20 THEN 'medium'
        ELSE 'large'
    END AS network_size_tier
FROM eedb015_silver.network n
LEFT JOIN net_plan_count npc
    ON npc.networkid = n.networkid AND npc.businessyear = n.businessyear
