CREATE TABLE IF NOT EXISTS eedb015_gold.dim_plan (
    plan_sk               STRING,
    plan_id_base          STRING,
    plan_id_full          STRING,
    business_year         INT,
    plan_name             STRING,
    metal_level           STRING,
    plan_type             STRING,
    issuer_id             STRING,
    state_code            STRING,
    network_id            STRING,
    service_area_id       STRING,
    market_coverage       STRING,
    is_dental_only        BOOLEAN,
    is_new_plan           BOOLEAN,
    wellness_program      BOOLEAN,
    national_network      BOOLEAN,
    ehb_pct_premium       DOUBLE,
    moop_individual       DOUBLE,
    deductible_individual DOUBLE,
    plan_lineage_id_2014  STRING,
    plan_lineage_id_2015  STRING,
    plan_lineage_id_2016  STRING,
    network_plan_count    INT
)
PARTITIONED BY (business_year)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_plan/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
