CREATE TABLE IF NOT EXISTS eedb015_gold.dim_network (
    network_sk        STRING,
    network_id        STRING,
    network_name      STRING,
    issuer_id         STRING,
    state_code        STRING,
    business_year     INT,
    plan_count        INT,
    network_size_tier STRING
)
PARTITIONED BY (business_year)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_network/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
