CREATE TABLE IF NOT EXISTS eedb015_gold.fct_market_competition (
    geo_sk                    STRING,
    year_sk                   INT,
    num_active_issuers        BIGINT,
    num_active_plans          BIGINT,
    avg_premium_individual    DOUBLE,
    median_premium_individual DOUBLE,
    competition_tier          STRING
)
PARTITIONED BY (year_sk)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/fct_market_competition/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
