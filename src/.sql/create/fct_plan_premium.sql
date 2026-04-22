CREATE TABLE IF NOT EXISTS eedb015_gold.fct_plan_premium (
    plan_sk              STRING,
    geo_sk               STRING,
    year_sk              INT,
    age                  INT,
    tobacco_flag         STRING,
    avg_individual_rate  DOUBLE,
    min_individual_rate  DOUBLE,
    max_individual_rate  DOUBLE,
    rate_count           BIGINT
)
PARTITIONED BY (year_sk)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/fct_plan_premium/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
