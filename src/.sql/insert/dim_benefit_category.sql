INSERT INTO eedb015_gold.dim_benefit_category
WITH benefit_base AS (
    SELECT
        benefitname,
        BOOL_OR(isehb) AS is_ehb_standard
    FROM eedb015_silver.benefits_cost_sharing
    GROUP BY benefitname
)
SELECT
    to_hex(md5(to_utf8(benefitname)))   AS benefit_sk,
    benefitname                         AS benefit_name,
    CASE
        WHEN benefitname IN ('Chemotherapy', 'Radiation Therapy', 'Infusion Therapy')
            THEN 'oncology'
        WHEN benefitname LIKE '%Preventive%'
          OR benefitname LIKE '%Well Baby%'
          OR benefitname LIKE '%Well Child%'
            THEN 'preventive'
        WHEN benefitname LIKE '%Mental%'
          OR benefitname LIKE '%Behavioral%'
          OR benefitname LIKE '%Substance Abuse%'
            THEN 'mental_health'
        WHEN benefitname LIKE '%Primary Care%'
            THEN 'primary_care'
        WHEN benefitname = 'Specialist Visit'
            THEN 'specialist'
        WHEN benefitname LIKE '%Emergency%'
          OR benefitname LIKE '%Urgent Care%'
          OR benefitname LIKE '%Ambulance%'
            THEN 'emergency'
        WHEN benefitname LIKE '%Drug%'
          OR benefitname LIKE '%Drugs%'
            THEN 'pharmacy'
        WHEN benefitname LIKE '%Maternity%'
          OR benefitname LIKE '%Newborn%'
            THEN 'maternity'
        WHEN benefitname LIKE '%Home Health%'
          OR benefitname LIKE '%Skilled Nursing%'
          OR benefitname LIKE '%Rehabilitat%'
          OR benefitname LIKE '%Habilitat%'
            THEN 'chronic_mgmt'
        WHEN benefitname LIKE '%Dental%'
          OR benefitname LIKE '%Eye%'
          OR benefitname LIKE '%Vision%'
          OR benefitname LIKE '%Orthodont%'
            THEN 'dental_vision'
        ELSE 'other'
    END AS benefit_category,
    benefitname IN ('Chemotherapy', 'Radiation Therapy', 'Infusion Therapy')
        AS is_oncology,
    (benefitname LIKE '%Preventive%'
     OR benefitname LIKE '%Well Baby%'
     OR benefitname LIKE '%Well Child%')
        AS is_preventive,
    (benefitname LIKE '%Mental%'
     OR benefitname LIKE '%Behavioral%'
     OR benefitname LIKE '%Substance Abuse%')
        AS is_mental_health,
    (benefitname LIKE '%Home Health%'
     OR benefitname LIKE '%Skilled Nursing%'
     OR benefitname LIKE '%Rehabilitat%')
        AS is_chronic,
    is_ehb_standard
FROM benefit_base
