-- Q3-D — Dataset analitico: uma linha por plano com preco + features estruturais + cobertura
-- Uso no Power BI: scatter plot (pct_cobertura x preco_mensal_usd, cor = nivel_metalico).
-- O agrupamento por cor de metal_level forma clusters verticais que nao se alinham com o eixo
-- de cobertura -> demonstra que metal_level explica preco independente de beneficios.
-- Tambem habilita: slicer por plan_type, porte_rede, estado para analise multivariada.
WITH benefit_features AS (
    SELECT
        fbc.plan_sk,
        fbc.year_sk,
        COUNT(*)                                                                   AS total_beneficios,
        SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                           AS beneficios_cobertos,
        ROUND(
            100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
            2
        )                                                                          AS pct_cobertura,
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.copay_inn_tier1 IS NOT NULL
                       THEN fbc.copay_inn_tier1 END), 2)                           AS copay_medio,
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.coins_inn_tier1 IS NOT NULL
                       THEN fbc.coins_inn_tier1 END) * 100, 2)                     AS coinsurance_medio_pct,
        -- Flags de categorias criticas (via dim_benefit_category)
        MAX(CASE WHEN dbc.is_oncology      AND fbc.is_covered THEN 1 ELSE 0 END)  AS tem_oncologia,
        MAX(CASE WHEN dbc.is_preventive    AND fbc.is_covered THEN 1 ELSE 0 END)  AS tem_preventivo,
        MAX(CASE WHEN dbc.is_mental_health AND fbc.is_covered THEN 1 ELSE 0 END)  AS tem_saude_mental,
        MAX(CASE WHEN dbc.is_chronic       AND fbc.is_covered THEN 1 ELSE 0 END)  AS tem_cronico,
        -- Contagem de beneficios cobertos por categoria (peso de cada area)
        SUM(CASE WHEN dbc.benefit_category = 'pharmacy'     AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_farmacia,
        SUM(CASE WHEN dbc.benefit_category = 'maternity'    AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_maternidade,
        SUM(CASE WHEN dbc.benefit_category = 'emergency'    AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_emergencia,
        SUM(CASE WHEN dbc.benefit_category = 'specialist'   AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_especialista,
        SUM(CASE WHEN dbc.benefit_category = 'primary_care' AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_atencao_basica,
        SUM(CASE WHEN dbc.benefit_category = 'oncology'     AND fbc.is_covered THEN 1 ELSE 0 END) AS qtd_oncologia
    FROM eedb015_gold.fct_benefit_coverage fbc
    JOIN eedb015_gold.dim_benefit_category dbc ON dbc.benefit_sk = fbc.benefit_sk
    GROUP BY 1, 2
),
plan_price AS (
    SELECT
        plan_sk,
        year_sk,
        ROUND(AVG(avg_individual_rate), 2)    AS preco_medio,
        ROUND(MIN(min_individual_rate), 2)    AS preco_min,
        ROUND(MAX(max_individual_rate), 2)    AS preco_max,
        -- Proxy de cobertura geografica: quantas areas de tarifacao o plano cobre
        CAST(SUM(rate_count) AS BIGINT)       AS qtd_registros_tarifacao
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    dp.business_year                                                               AS ano,
    dp.state_code                                                                  AS estado,
    dp.plan_id_base                                                                AS plano_id,
    dp.plan_name                                                                   AS nome_plano,
    dp.metal_level                                                                 AS nivel_metalico,
    dp.plan_type                                                                   AS tipo_plano,
    -- Features de rede (variaveis estruturais nao-beneficio)
    dn.network_size_tier                                                           AS porte_rede,
    dp.network_plan_count                                                          AS planos_na_rede,
    CAST(dp.national_network AS INT)                                               AS rede_nacional,
    -- Features do plano
    CAST(dp.is_new_plan      AS INT)                                               AS plano_novo,
    CAST(dp.wellness_program AS INT)                                               AS tem_wellness,
    -- EHB%: fracao do premio destinada a cobertura mandatada (variavel de precificacao direta)
    ROUND(dp.ehb_pct_premium * 100, 2)                                             AS pct_premio_ehb,
    ROUND(dp.moop_individual, 0)                                                   AS moop_individual_usd,
    ROUND(dp.deductible_individual, 0)                                             AS deductible_usd,
    -- Preco (variavel dependente)
    pp.preco_medio                                                                 AS preco_mensal_usd,
    pp.preco_min                                                                   AS preco_min_usd,
    pp.preco_max                                                                   AS preco_max_usd,
    pp.qtd_registros_tarifacao                                                     AS cobertura_geografica,
    -- Score de cobertura de beneficios (variavel independente principal da Q3)
    bf.total_beneficios,
    bf.beneficios_cobertos,
    bf.pct_cobertura,
    bf.copay_medio,
    bf.coinsurance_medio_pct,
    -- Flags e contagens por categoria
    bf.tem_oncologia,
    bf.tem_preventivo,
    bf.tem_saude_mental,
    bf.tem_cronico,
    bf.qtd_farmacia,
    bf.qtd_maternidade,
    bf.qtd_emergencia,
    bf.qtd_especialista,
    bf.qtd_atencao_basica,
    bf.qtd_oncologia
FROM eedb015_gold.dim_plan dp
JOIN plan_price pp        ON pp.plan_sk = dp.plan_sk AND pp.year_sk = dp.business_year
JOIN benefit_features bf  ON bf.plan_sk = dp.plan_sk AND bf.year_sk = dp.business_year
LEFT JOIN eedb015_gold.dim_network dn
    ON  dn.network_id     = dp.network_id
    AND dn.state_code     = dp.state_code
    AND dn.business_year  = dp.business_year
WHERE dp.is_dental_only = FALSE
  AND dp.market_coverage = 'Individual'
ORDER BY dp.business_year, dp.state_code, pp.preco_medio DESC
