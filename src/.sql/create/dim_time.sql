CREATE TABLE IF NOT EXISTS eedb015_gold.dim_time (
    business_year INT,
    year_label    STRING,
    aca_phase     STRING
)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_time/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
