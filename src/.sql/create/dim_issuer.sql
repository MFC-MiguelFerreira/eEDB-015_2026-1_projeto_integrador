CREATE TABLE IF NOT EXISTS eedb015_gold.dim_issuer (
    issuer_sk         STRING,
    issuer_id         STRING,
    business_year     INT,
    state_code        STRING,
    num_plans_offered INT,
    num_networks      INT,
    avg_network_size  INT
)
PARTITIONED BY (business_year)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_issuer/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
