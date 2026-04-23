CREATE TABLE IF NOT EXISTS eedb015_gold.dim_benefit_category (
    benefit_sk       STRING,
    benefit_name     STRING,
    benefit_category STRING,
    is_oncology      BOOLEAN,
    is_preventive    BOOLEAN,
    is_mental_health BOOLEAN,
    is_chronic       BOOLEAN,
    is_ehb_standard  BOOLEAN
)
LOCATION 's3://<ACCOUNT_ID>-eedb015-gold/gold/dim_benefit_category/'
TBLPROPERTIES ('table_type'='iceberg', 'format'='parquet')
