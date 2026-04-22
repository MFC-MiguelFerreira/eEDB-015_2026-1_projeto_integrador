CREATE TABLE IF NOT EXISTS eedb015_gold.dim_geography (
    geo_sk               STRING,
    state_code           STRING,
    state_name           STRING,
    census_region        STRING,
    census_division      STRING,
    num_counties_covered INT
)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_geography/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
