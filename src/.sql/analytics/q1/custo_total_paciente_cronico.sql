-- Q1 — Qual nível metálico minimiza o custo total do paciente crônico?
-- Estimativa de pior caso: custo do benefício oncológico mais caro coberto pelo plano
-- (Chemotherapy ou Infusion Therapy) × 12 sessões + prêmio anual, limitado ao MOOP.
WITH oncology_cost AS (
    -- Uma linha por plano: pega o pior caso entre os benefícios oncológicos cobertos
    SELECT
        fbc.year_sk,
        dp.plan_sk,
        dp.metal_level,
        dp.deductible_individual,
        dp.moop_individual,
        -- MAX garante pior caso quando o plano cobre ambos Chemotherapy e Infusion Therapy
        MAX(
            COALESCE(fbc.copay_inn_tier1,
                     fbc.coins_inn_tier1 * dp.moop_individual, 0)
        )                                                             AS estimated_session_cost,
        -- Deductible efetivo: 0 se nenhum benefício coberto exige esgotamento prévio
        MAX(CASE WHEN fbc.is_subj_to_ded THEN dp.deductible_individual ELSE 0 END)
                                                                      AS deductible_efetivo
    FROM eedb015_gold.fct_benefit_coverage  fbc
    JOIN eedb015_gold.dim_plan              dp  ON dp.plan_sk    = fbc.plan_sk
    JOIN eedb015_gold.dim_benefit_category  dbc ON dbc.benefit_sk = fbc.benefit_sk
    WHERE dbc.benefit_name   IN ('Chemotherapy', 'Infusion Therapy')
      AND fbc.is_covered     = TRUE
      AND dp.is_dental_only  = FALSE
      AND dp.market_coverage = 'Individual'
    GROUP BY 1, 2, 3, 4, 5
),
premium_27 AS (
    SELECT plan_sk, year_sk, AVG(avg_individual_rate) AS avg_monthly_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    oc.year_sk                                                                    AS ano,
    oc.metal_level                                                                AS nivel_metalico,
    COUNT(DISTINCT oc.plan_sk)                                                    AS total_planos,
    ROUND(AVG(oc.deductible_efetivo),    2)                                       AS deductible_medio,
    ROUND(AVG(oc.moop_individual),       2)                                       AS moop_individual_medio,
    ROUND(AVG(oc.estimated_session_cost * 12),   2)                               AS custo_tratamento_anual_est,
    ROUND(AVG(p.avg_monthly_rate * 12),  2)                                       AS custo_premio_anual,
    -- LEAST: paciente nunca paga além do MOOP anual, independente do nº de sessões
    ROUND(AVG(
        LEAST(oc.estimated_session_cost * 12, oc.moop_individual)
        + p.avg_monthly_rate * 12
    ), 2)                                                                          AS custo_total_paciente_est
FROM oncology_cost oc
JOIN premium_27    p  ON p.plan_sk = oc.plan_sk AND p.year_sk = oc.year_sk
GROUP BY 1, 2
ORDER BY
    oc.year_sk,
    CASE oc.metal_level
        WHEN 'Bronze'   THEN 1
        WHEN 'Silver'   THEN 2
        WHEN 'Gold'     THEN 3
        WHEN 'Platinum' THEN 4
        ELSE 5
    END
