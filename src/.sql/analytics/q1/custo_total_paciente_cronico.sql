-- Q1 — Qual nível metálico minimiza o custo total do paciente crônico?
-- (proxy: 12 sessões/ano × custo por sessão + prêmio anual)
WITH oncology_cost AS (
    SELECT
        fbc.year_sk,
        dp.metal_level,
        dp.plan_sk,
        COALESCE(fbc.copay_inn_tier1,
                 fbc.coins_inn_tier1 * dp.moop_individual, 0) AS estimated_session_cost,
        dp.moop_individual
    FROM eedb015_gold.fct_benefit_coverage fbc
    JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = fbc.plan_sk
    JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
    WHERE dbc.benefit_name IN ('Chemotherapy', 'Infusion Therapy')
      AND fbc.is_covered = TRUE
      AND dp.is_dental_only = FALSE
),
premium_27 AS (
    SELECT plan_sk, year_sk, avg_individual_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
)
SELECT
    oc.year_sk                                                       AS ano,
    oc.metal_level                                                   AS nivel_metalico,
    ROUND(AVG(oc.estimated_session_cost * 12), 2)                   AS custo_tratamento_anual_est,
    ROUND(AVG(p.avg_individual_rate * 12), 2)                       AS custo_premio_anual,
    ROUND(AVG(oc.moop_individual), 2)                               AS moop_individual_medio,
    ROUND(AVG(
        LEAST(oc.estimated_session_cost * 12, oc.moop_individual)
        + p.avg_individual_rate * 12
    ), 2)                                                            AS custo_total_paciente_est
FROM oncology_cost oc
JOIN premium_27 p ON p.plan_sk = oc.plan_sk AND p.year_sk = oc.year_sk
GROUP BY 1, 2
ORDER BY oc.year_sk, custo_total_paciente_est
