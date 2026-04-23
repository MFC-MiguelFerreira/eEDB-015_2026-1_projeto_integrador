# Silver Layer Reference for Gold Development

> Based on notebook `silver_exploration.ipynb` outputs. Optimized for token efficiency.

---

## ⚠️ Critical: PlanId Format Incompatibility

| Table | Format | Length | Example |
|-------|--------|--------|---------|
| `rate`, `crosswalk2015`, `crosswalk2016` | No suffix | 14 | `21989AK0010001` |
| `plan_attributes`, `benefits_cost_sharing`, `business_rules` | With `-XX` suffix | 17 | `21989AK0020002-00` |

**Join `rate` → `plan_attributes`:**
```sql
ON SUBSTR(pa.PlanId, 1, 14) = r.PlanId AND pa.BusinessYear = r.BusinessYear
```

**Keep base plans only (exclude CSR variants):** `WHERE RIGHT(PlanId, 2) = '00'`

---

## 1. `rate` – Premiums
**Rows:** 12.7M | **Cols:** 26

### Schema

| Column Name | Type | Partition |
|-------------|------|-----------|
| businessyear | int | False |
| statecode | string | False |
| issuerid | string | False |
| sourcename | string | False |
| versionnum | string | False |
| importdate | timestamp | False |
| issuerid2 | string | False |
| federaltin | string | False |
| rateeffectivedate | timestamp | False |
| rateexpirationdate | timestamp | False |
| planid | string | False |
| ratingareaid | string | False |
| tobacco | string | False |
| age | int | False |
| individualrate | double | False |
| individualtobaccorate | double | False |
| couple | double | False |
| primarysubscriberandonedependent | double | False |
| primarysubscriberandtwodependents | double | False |
| primarysubscriberandthreeormoredependents | double | False |
| coupleandonedependent | double | False |
| coupleandtwodependents | double | False |
| coupleandthreeormoredependents | double | False |
| rownumber | string | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### Schema (key columns)
| Column | Type | Null % |
|--------|------|--------|
| `businessyear` | int | 0% |
| `statecode` | string | 0% |
| `issuerid` | string | 0% |
| `planid` | string | 0% |
| `age` | int | 4.66% |
| `tobacco` | string | 0% |
| `individualrate` | double | 0% |
| `individualtobaccorate` | double | 61.15% |
| `ratingareaid` | string | 0% |

### Distributions
**Tobacco:**
| value | count | pct |
|-------|-------|-----|
| No Preference | 7,804,323 | 61.48% |
| Tobacco User/Non-Tobacco User | 4,890,122 | 38.52% |

**Age:** Rows per age from 21 to 64, each ~275K rows (uniform)

### Numeric stats
| Column | Min | Max | Avg |
|--------|-----|-----|-----|
| `individualrate` | 0 | 999,999 | 4,098 |
| `individualtobaccorate` | 41.73 | 6,604.61 | 543.69 |

### By Year
| Year | Rows | Distinct Plans | Min Rate | Max Rate | Avg Rate |
|------|------|----------------|----------|----------|----------|
| 2014 | 3,796,388 | 6,633 | 0 | 999,999 | 12,922 |
| 2015 | 4,676,092 | 10,095 | 0 | 9,999.99 | 329 |
| 2016 | 4,221,965 | 8,887 | 0 | 9,999 | 338 |

### Gold filters
```sql
WHERE IndividualRate BETWEEN 0 AND 3000
  AND Age != 'Family Option'
```

---

## 2. `plan_attributes` – Plan catalog
**Rows:** 77K | **Cols:** 178

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| avcalculatoroutputnumber | string | False |
| beginprimarycarecostsharingafternumberofvisits | int | False |
| beginprimarycaredeductiblecoinsuranceafternumberofcopays | int | False |
| benefitpackageid | int | False |
| businessyear | int | False |
| csrvariationtype | string | False |
| childonlyoffering | string | False |
| childonlyplanid | string | False |
| compositeratingoffered | string | False |
| dehbcombinnoonfamilymoop | double | False |
| dehbcombinnoonfamilypergroupmoop | string | False |
| dehbcombinnoonfamilyperpersonmoop | string | False |
| dehbcombinnoonindividualmoop | double | False |
| dehbdedcombinnoonfamily | double | False |
| dehbdedcombinnoonfamilypergroup | string | False |
| dehbdedcombinnoonfamilyperperson | string | False |
| dehbdedcombinnoonindividual | double | False |
| dehbdedinntier1coinsurance | double | False |
| dehbdedinntier1family | double | False |
| dehbdedinntier1familypergroup | string | False |
| dehbdedinntier1familyperperson | string | False |
| dehbdedinntier1individual | double | False |
| dehbdedinntier2coinsurance | double | False |
| dehbdedinntier2family | double | False |
| dehbdedinntier2familypergroup | string | False |
| dehbdedinntier2familyperperson | string | False |
| dehbdedinntier2individual | double | False |
| dehbdedoutofnetfamily | double | False |
| dehbdedoutofnetfamilypergroup | string | False |
| dehbdedoutofnetfamilyperperson | string | False |
| dehbdedoutofnetindividual | double | False |
| dehbinntier1familymoop | double | False |
| dehbinntier1familypergroupmoop | string | False |
| dehbinntier1familyperpersonmoop | string | False |
| dehbinntier1individualmoop | double | False |
| dehbinntier2familymoop | string | False |
| dehbinntier2familypergroupmoop | string | False |
| dehbinntier2familyperpersonmoop | string | False |
| dehbinntier2individualmoop | string | False |
| dehboutofnetfamilymoop | double | False |

### Schema (key columns)
| Column | Type | Null % |
|--------|------|--------|
| `businessyear` | int | 0% |
| `statecode` | string | 0% |
| `issuerid` | string | 0% |
| `planid` (with suffix) | string | 0% |
| `metallevel` | string | 0% |
| `plantype` | string | 0% |
| `networkid` | string | 0% |
| `serviceareaid` | string | 0.02% |
| `isnewplan` | boolean | 0% |
| `csrvariationtype` | string | 0% |
| `mehbinn tier1individualmoop` | double | 84.98% |
| `ehbpercenttotalpremium` | double | 70.12% |

### MetalLevel × PlanType distribution (top)
| Year | MetalLevel | PlanType | Count | Issuers | States |
|------|------------|---------|-------|---------|--------|
| 2014 | Silver | HMO | 3,118 | 97 | 26 |
| 2014 | Silver | PPO | 2,607 | 89 | 33 |
| 2014 | Low | PPO | 1,590 | 248 | 36 |
| 2014 | Bronze | HMO | 1,559 | 94 | 27 |

### CSRVariationType (top values)
| Value | Count | % |
|-------|-------|---|
| Zero Cost Sharing Plan Variation | 10,745 | 13.89% |
| Limited Cost Sharing Plan Variation | 10,745 | 13.89% |
| Standard Silver On Exchange Plan | 6,054 | 7.83% |

### Numeric stats (MOOP/Deductible)
| Column | Min | Max | Avg |
|--------|-----|-----|-----|
| `mehbinn tier1individualmoop` | 0 | 6,350 | 658 |
| `mehbd edinntier1individual` | 0 | 6,850 | 1,390 |

---

## 3. `benefits_cost_sharing` – Benefits & cost sharing
**Rows:** 5M | **Cols:** 34

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| benefitname | string | False |
| businessyear | int | False |
| coinsinntier1 | double | False |
| coinsinntier2 | double | False |
| coinsoutofnet | double | False |
| copayinntier1 | double | False |
| copayinntier2 | double | False |
| copayoutofnet | double | False |
| ehbvarreason | string | False |
| exclusions | string | False |
| explanation | string | False |
| importdate | timestamp | False |
| iscovered | boolean | False |
| isehb | boolean | False |
| isexclfrominnmoop | boolean | False |
| isexclfromoonmoop | boolean | False |
| isstatemandate | boolean | False |
| issubjtodedtier1 | boolean | False |
| issubjtodedtier2 | boolean | False |
| issuerid | string | False |
| issuerid2 | string | False |
| limitqty | int | False |
| limitunit | string | False |
| minimumstay | int | False |
| planid | string | False |
| quantlimitonsvc | boolean | False |
| rownumber | string | False |
| sourcename | string | False |
| standardcomponentid | string | False |
| statecode | string | False |
| statecode2 | string | False |
| versionnum | string | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### Schema (key columns)
| Column | Type | Null % |
|--------|------|--------|
| `benefitname` | string | 0% |
| `businessyear` | int | 0% |
| `planid` (with suffix) | string | 0% |
| `iscovered` | boolean | 4.28% |
| `isehb` | boolean | 36.02% |
| `issubjtodedtier1` | boolean | 48.86% |
| `copayinntier1` | double | 46.61% |
| `coinsinntier1` | double | 71.62% |
| `limitqty` | int | 86.37% |

### Null semantics
- `CoinsInnTier1 IS NULL` → copay applies (fixed dollar)
- `CopayInnTier1 IS NULL` → coinsurance applies (percentage)

### Top BenefitName (by frequency)
| BenefitName | Count | % |
|-------------|-------|---|
| Routine Dental Services (Adult) | 77,323 | 1.53% |
| Orthodontia - Adult | 77,323 | 1.53% |
| Major Dental Care - Child | 77,323 | 1.53% |
| (30+ benefits each ~1.3%) | | |

### Oncology analysis (2014-2016)
| Year | Benefit | Plans | Covered % | Avg Copay | Avg Coinsurance |
|------|---------|-------|-----------|-----------|-----------------|
| 2014 | Chemotherapy | 15,157 | 98.2% | $2.94 | 4.0% |
| 2015 | Chemotherapy | 26,991 | 99.1% | $1.52 | 2.4% |
| 2016 | Chemotherapy | 23,482 | 99.2% | $6.48 | 2.3% |

---

## 4. `service_area` – Geographic coverage
**Rows:** 42K | **Cols:** 20

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| businessyear | int | False |
| statecode | string | False |
| issuerid | string | False |
| sourcename | string | False |
| versionnum | string | False |
| importdate | timestamp | False |
| issuerid2 | string | False |
| statecode2 | string | False |
| serviceareaid | string | False |
| serviceareaname | string | False |
| coverentirestate | boolean | False |
| county | string | False |
| partialcounty | boolean | False |
| zipcodes | string | False |
| partialcountyjustification | string | False |
| rownumber | string | False |
| marketcoverage | string | False |
| dentalonlyplan | boolean | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### Schema (key columns)
| Column | Type | Null % |
|--------|------|--------|
| `serviceareaid` | string | 0% |
| `businessyear` | int | 0% |
| `statecode` | string | 0% |
| `issuerid` | string | 0% |
| `county` | string | 4.25% |
| `coverentirestate` | boolean | 0% |
| `zipcodes` | string | 98.54% |

### CoverEntireState by year
| Year | CoverEntireState | Rows | Distinct Issuers |
|------|-----------------|------|------------------|
| 2014 | False | 8,473 | 185 |
| 2014 | True | 401 | 298 |
| 2015 | False | 16,825 | 303 |
| 2016 | False | 15,154 | 299 |

### Competition by state (top 2014)
| State | Issuers |
|-------|---------|
| TX | 27 |
| MI | 25 |
| PA | 25 |
| FL | 24 |

---

## 5. `business_rules` – Eligibility
**Rows:** 21K | **Cols:** 25

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| businessyear | int | False |
| statecode | string | False |
| issuerid | string | False |
| sourcename | string | False |
| versionnum | string | False |
| importdate | timestamp | False |
| issuerid2 | string | False |
| tin | string | False |
| productid | string | False |
| standardcomponentid | string | False |
| enrolleecontractratedeterminationrule | string | False |
| twoparentfamilymaxdependentsrule | string | False |
| singleparentfamilymaxdependentsrule | string | False |
| dependentmaximumagrule | int | False |
| childrenonlycontractmaxchildrenrule | string | False |
| domesticpartnerasspouseindicator | boolean | False |
| samesexpartnerasspouseindicator | boolean | False |
| agedeterminationrule | string | False |
| minimumtobaccofreemonthsrule | int | False |
| cohabitationrule | string | False |
| rownumber | string | False |
| marketcoverage | string | False |
| dentalonlyplan | boolean | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### Schema (key columns)
| Column | Type | Null % |
|--------|------|--------|
| `businessyear` | int | 0% |
| `planid` (with suffix) | string | 0% |
| `marketcoverage` | string | 5.73% |
| `dentalonlyplan` | boolean | 5.73% |

### MarketCoverage distribution
| Value | Count | % |
|-------|-------|---|
| Individual | 11,043 | 52.37% |
| SHOP (Small Group) | 8,834 | 41.90% |
| NULL | 1,208 | 5.73% |

---

## 6. `crosswalk2015` – Lineage 2014→2015
**Rows:** 132K | **Cols:** 23

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| state | string | False |
| dentalplan | boolean | False |
| planid_2014 | string | False |
| issuerid_2014 | string | False |
| multistateplan_2014 | boolean | False |
| metallevel_2014 | string | False |
| childadultonly_2014 | int | False |
| fipscode | string | False |
| zipcode | string | False |
| crosswalklevel | int | False |
| reasonforcrosswalk | int | False |
| planid_2015 | string | False |
| issuerid_2015 | string | False |
| multistateplan_2015 | boolean | False |
| metallevel_2015 | string | False |
| childadultonly_2015 | int | False |
| ageoffplanid_2015 | string | False |
| issuerid_ageoff2015 | string | False |
| multistateplan_ageoff2015 | string | False |
| metallevel_ageoff2015 | string | False |
| childadultonly_ageoff2015 | string | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### CrosswalkLevel distribution
| Level | Count | % |
|-------|-------|---|
| 0 | 70,756 | 53.40% |
| 1 | 31,438 | 23.73% |
| 2 | 17,177 | 12.96% |
| 4 | 7,661 | 5.78% |
| 3 | 5,473 | 4.13% |

### No nulls in `planid_2014` or `planid_2015`

---

## 7. `crosswalk2016` – Lineage 2015→2016
**Rows:** 150K | **Cols:** 23

### Schema

Here is the Markdown table structure for the `crosswalk2016` schema:

| Column Name | Type | Partition |
|-------------|------|-----------|
| state | string | False |
| dentalplan | boolean | False |
| planid_2015 | string | False |
| issuerid_2015 | string | False |
| multistateplan_2015 | boolean | False |
| metallevel_2015 | string | False |
| childadultonly_2015 | int | False |
| fipscode | string | False |
| zipcode | string | False |
| crosswalklevel | int | False |
| reasonforcrosswalk | int | False |
| planid_2016 | string | False |
| issuerid_2016 | string | False |
| multistateplan_2016 | boolean | False |
| metallevel_2016 | string | False |
| childadultonly_2016 | int | False |
| ageoffplanid_2016 | string | False |
| issuerid_ageoff2016 | string | False |
| multistateplan_ageoff2016 | string | False |
| metallevel_ageoff2016 | string | False |
| childadultonly_ageoff2016 | string | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### CrosswalkLevel distribution
| Level | Count | % |
|-------|-------|---|
| 0 | 82,294 | 54.86% |
| 1 | 34,248 | 22.83% |
| 2 | 15,301 | 10.20% |
| 4 | 14,552 | 9.70% |
| 3 | 2,245 | 1.50% |
| 5 | 1,365 | 0.91% |

---

## 8. `network` – Provider networks
**Rows:** 3.8K | **Cols:** 16

### Schema

Here is the Markdown table structure for the schema you provided:

| Column Name | Type | Partition |
|-------------|------|-----------|
| businessyear | int | False |
| statecode | string | False |
| issuerid | string | False |
| sourcename | string | False |
| versionnum | string | False |
| importdate | timestamp | False |
| issuerid2 | string | False |
| statecode2 | string | False |
| networkname | string | False |
| networkid | string | False |
| networkurl | string | False |
| rownumber | string | False |
| marketcoverage | string | False |
| dentalonlyplan | boolean | False |
| landinzone_path | string | False |
| ingestion_datetime | timestamp | False |

### Schema (key columns)
| Column | Type |
|--------|------|
| `networkid` | string |
| `businessyear` | int |
| `statecode` | string |
| `issuerid` | string |
| `networkname` | string |

### By year
| Year | Rows | Distinct Networks | Distinct Issuers |
|------|------|-------------------|------------------|
| 2014 | 937 | 179 | 444 |
| 2015 | 1,459 | 248 | 783 |
| 2016 | 1,426 | 232 | 770 |

---

## Gold Table Construction Summary

| Gold Table | Base Tables | Join Keys | Group By |
|------------|-------------|-----------|----------|
| `gold_oncology_copay` | benefits, plan_attributes | PlanId (with suffix) | BenefitName, MetalLevel, Year |
| `gold_competition_pricing` | rate, service_area | StateCode, Year | StateCode, Year |
| `gold_benefit_pricing` | benefits, rate, plan_attributes | PlanId (14→17) | PlanId, Year |
| `gold_network_pricing` | network, plan_attributes, rate | NetworkId | NetworkId, StateCode, Year |
| `gold_geographic_monopoly` | service_area, rate, plan_attributes | StateCode, County | County, StateCode, Year |

---

## Standard Filters for All Gold Queries

```sql
WHERE DentalOnlyPlan = FALSE
  AND MarketCoverage = 'Individual'
  AND RIGHT(PlanId, 2) = '00'           -- base plans only
  AND IndividualRate > 0 AND IndividualRate < 3000
  AND Age != 'Family Option'
```