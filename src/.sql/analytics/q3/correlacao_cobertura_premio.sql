-- Q3-A — Correlação entre score de cobertura e prêmio, por nível metálico e tipo de plano
-- Responde: benefícios explicam variação de preço?
--   CORR(cobertura, prêmio) por célula (metal × plan_type × ano) isola o efeito estrutural.
--   desvio_padrao_premio mostra quanta dispersão de preço PERSISTE dentro de mesma célula —
--   se alto, outros fatores (rede, estado, EHB%) dominam sobre cobertura de benefícios.
-- Visual principal: matriz heat map (metal_level × plan_type), valor = corr_cobertura_premio,
--   slicer por ano. Visual secundário: scatter desvio_padrao vs pct_cobertura_media por célula.
WITH benefit_score AS (
    SELECT
        fbc.plan_sk,
        fbc.year_sk,
        COUNT(*)                                                                   AS total_beneficios,
        SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END)                           AS beneficios_cobertos,
        ROUND(
            100.0 * SUM(CASE WHEN fbc.is_covered THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
            1
        )                                                                          AS pct_cobertura,
        -- Copay real: exclui planos sem estrutura copay (não conflate com copay=0)
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.copay_inn_tier1 IS NOT NULL
                       THEN fbc.copay_inn_tier1 END), 2)                           AS copay_medio_quando_existe,
        ROUND(AVG(CASE WHEN fbc.is_covered AND fbc.coins_inn_tier1 IS NOT NULL
                       THEN fbc.coins_inn_tier1 END) * 100, 2)                     AS coinsurance_medio_pct,
        -- % dos benefícios cobertos que usam copay (vs coinsurance)
        ROUND(
            100.0
            * SUM(CASE WHEN fbc.is_covered AND fbc.copay_inn_tier1 IS NOT NULL THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fbc.is_covered THEN 1 END), 0),
            1
        )                                                                          AS pct_beneficios_com_copay
    FROM eedb015_gold.fct_benefit_coverage fbc
    GROUP BY 1, 2
),
plan_price AS (
    SELECT
        plan_sk,
        year_sk,
        ROUND(AVG(avg_individual_rate), 2)   AS avg_rate
    FROM eedb015_gold.fct_plan_premium
    WHERE age = 27 AND tobacco_flag = 'No Preference'
    GROUP BY 1, 2
)
SELECT
    dp.metal_level,
    dp.plan_type,
    bs.year_sk                                                                     AS ano,
    COUNT(*)                                                                       AS qtd_planos,
    -- Score de cobertura
    ROUND(AVG(bs.beneficios_cobertos), 1)                                          AS media_beneficios_cobertos,
    ROUND(AVG(bs.pct_cobertura), 1)                                                AS media_pct_cobertura,
    -- Estrutura de cost-sharing (sem distorção de COALESCE)
    ROUND(AVG(bs.pct_beneficios_com_copay), 1)                                     AS pct_beneficios_com_copay,
    ROUND(AVG(bs.copay_medio_quando_existe), 2)                                    AS copay_medio_usd,
    ROUND(AVG(bs.coinsurance_medio_pct), 2)                                        AS coinsurance_medio_pct,
    -- Prêmio e dispersão dentro da célula (metal × plan_type × ano)
    ROUND(AVG(pp.avg_rate), 2)                                                     AS premio_medio_usd,
    ROUND(STDDEV(pp.avg_rate), 2)                                                  AS desvio_padrao_premio,
    ROUND(MIN(pp.avg_rate), 2)                                                     AS premio_min_usd,
    ROUND(MAX(pp.avg_rate), 2)                                                     AS premio_max_usd,
    -- EHB% — fração do prêmio mandatada por lei; variável de precificação direta
    ROUND(AVG(dp.ehb_pct_premium) * 100, 2)                                        AS pct_premio_ehb_medio,
    -- MOOP e deductible médios da célula (contexto para custo total do paciente)
    ROUND(AVG(dp.moop_individual), 0)                                              AS moop_medio_usd,
    ROUND(AVG(dp.deductible_individual), 0)                                        AS deductible_medio_usd,
    -- Correlações de Pearson (benefícios → preço)
    ROUND(CORR(bs.pct_cobertura,       pp.avg_rate), 4)                            AS corr_cobertura_premio,
    ROUND(CORR(bs.beneficios_cobertos, pp.avg_rate), 4)                            AS corr_num_beneficios_premio,
    ROUND(CORR(dp.ehb_pct_premium,     pp.avg_rate), 4)                            AS corr_ehb_pct_premio
FROM benefit_score bs
JOIN eedb015_gold.dim_plan dp ON dp.plan_sk = bs.plan_sk
JOIN plan_price pp             ON pp.plan_sk = bs.plan_sk AND pp.year_sk = bs.year_sk
WHERE dp.is_dental_only = FALSE
  AND dp.market_coverage = 'Individual'
GROUP BY dp.metal_level, dp.plan_type, bs.year_sk
ORDER BY bs.year_sk, dp.metal_level, dp.plan_type
