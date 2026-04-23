CREATE TABLE IF NOT EXISTS eedb015_gold.fct_benefit_coverage (
    plan_sk          STRING,
    benefit_sk       STRING,
    year_sk          INT,
    is_covered       BOOLEAN,
    is_ehb           BOOLEAN,
    copay_inn_tier1  DOUBLE,
    coins_inn_tier1  DOUBLE,
    copay_out_of_net DOUBLE,
    coins_out_of_net DOUBLE,
    is_subj_to_ded   BOOLEAN,
    limit_qty        INT,
    cost_type        STRING
)
PARTITIONED BY (year_sk)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/fct_benefit_coverage/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
