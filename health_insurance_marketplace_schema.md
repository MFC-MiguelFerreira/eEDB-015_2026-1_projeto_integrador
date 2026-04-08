# Health Insurance Marketplace - Database Schema

This document describes the dimensional database schema for the Health Insurance Marketplace Data Warehouse project, including all tables, columns, and relationships following Kimball methodology.

## Entity Relationship Diagram

```mermaid
erDiagram
    FATO_PLANOS_MERCADO_SAUDE }|--|| DIM_TEMPO : "references"
    FATO_PLANOS_MERCADO_SAUDE }|--|| DIM_PLANO : "references"
    FATO_PLANOS_MERCADO_SAUDE }|--|| DIM_GEOGRAFIA : "references"
    FATO_PLANOS_MERCADO_SAUDE }|--|| DIM_PRESTADOR : "references"
    FATO_PLANOS_MERCADO_SAUDE }|--|| DIM_BENEFICIOS : "references"
    DIM_PLANO }|--|| DIM_PRESTADOR : "has_primary_provider"
    APOIO_CROSSWALK_PLANOS ||--o{ DIM_PLANO : "manages_lineage"

    FATO_PLANOS_MERCADO_SAUDE {
        BIGINT sk_tempo PK "Surrogate key - Dimensão Tempo"
        BIGINT sk_plano PK "Surrogate key - Dimensão Plano"
        BIGINT sk_geografia PK "Surrogate key - Dimensão Geografia"
        BIGINT sk_prestador FK "Surrogate key - Dimensão Prestador"
        BIGINT sk_beneficios FK "Surrogate key - Dimensão Benefícios"
        VARCHAR plan_id_original "ID original do plano no dataset"
        VARCHAR state_county_rating_area "Concatenação estado+condado+área"
        DECIMAL individual_rate "Taxa individual mensal"
        DECIMAL individual_tobacco_rate "Taxa individual para fumantes"
        DECIMAL couple_rate "Taxa para casal sem filhos"
        DECIMAL primary_adult_child_rate "Taxa adulto principal + criança"
        DECIMAL couple_child_rate "Taxa casal + criança"
        DECIMAL family_rate "Taxa familiar completa"
        DECIMAL small_group_rate "Taxa para pequenos grupos"
        DECIMAL deductible_individual "Franquia individual anual"
        DECIMAL deductible_family "Franquia familiar anual"
        DECIMAL medical_deductible_individual "Franquia médica individual"
        DECIMAL drug_deductible_individual "Franquia medicamentos individual"
        DECIMAL out_of_pocket_individual "Limite gastos individuais"
        DECIMAL out_of_pocket_family "Limite gastos familiares"
        DECIMAL copay_primary_care "Copagamento cuidados primários"
        DECIMAL copay_specialist "Copagamento especialista"
        DECIMAL copay_emergency_room "Copagamento emergência"
        DECIMAL copay_inpatient_facility "Copagamento internação"
        DECIMAL copay_generic_drugs "Copagamento medicamentos genéricos"
        DECIMAL copay_preferred_brand_drugs "Copagamento medicamentos marca"
        DECIMAL coinsurance_primary_care "Percentual cosseguro cuidados primários"
        DECIMAL coinsurance_specialist "Percentual cosseguro especialista"
        INTEGER numero_beneficiarios_inscritos "Número estimado de inscritos"
        DECIMAL receita_total_premios "Receita total estimada com prêmios"
        DECIMAL custo_total_sinistros "Custo total estimado com sinistros"
        DECIMAL margem_lucro_estimada "Margem de lucro estimada"
        DECIMAL indice_competitividade "Índice de competitividade regional"
        TIMESTAMP data_carga "Data/hora da carga dos dados"
        VARCHAR versao_crosswalk "Versão do crosswalk aplicado"
    }

    DIM_TEMPO {
        BIGINT sk_tempo PK "Surrogate key"
        DATE data_completa UK "Data completa YYYY-MM-DD"
        INTEGER ano "Ano"
        INTEGER trimestre "Trimestre (1-4)"
        INTEGER mes "Mês (1-12)"
        INTEGER ano_plano "Ano específico do plano (2014/2015/2016)"
        VARCHAR periodo_inscricao "Período de inscrição correspondente"
        BOOLEAN flag_ano_atual "Flag indicando se é o ano atual"
        BOOLEAN flag_mes_atual "Flag indicando se é o mês atual"
    }

    DIM_PLANO {
        BIGINT sk_plano PK "Surrogate key"
        VARCHAR plan_id_original UK "ID original do plano no dataset"
        VARCHAR hios_issuer_id "Identificador da seguradora HIOS"
        VARCHAR plan_id_crosswalk "ID do plano no crosswalk"
        VARCHAR linhagem_plano_id UK "ID unificado da linhagem temporal"
        VARCHAR plan_marketing_name "Nome comercial do plano"
        VARCHAR plan_type "Tipo do plano (HMO, PPO, EPO, POS)"
        VARCHAR metal_level "Nível metálico (Bronze, Silver, Gold, Platinum)"
        VARCHAR plan_variant_marketing_name "Nome comercial da variante"
        BOOLEAN hsa_eligible "Elegibilidade para Health Savings Account"
        BOOLEAN child_only_offering "Oferta específica para crianças"
        VARCHAR network_tier "Nível da rede de prestadores"
        VARCHAR formulary_id "Identificador do formulário de medicamentos"
        BOOLEAN is_plan_restrito_rede "Flag de rede restrita"
        VARCHAR status_plano "Status do plano (Ativo, Descontinuado)"
    }

    DIM_GEOGRAFIA {
        BIGINT sk_geografia PK "Surrogate key"
        VARCHAR state_code UK "Código do estado (2 letras)"
        VARCHAR county_name "Nome do condado"
        VARCHAR county_fips UK "Código FIPS do condado"
        VARCHAR zip_code "Código postal"
        VARCHAR rating_area UK "Área de rating para cálculo de prêmios"
        VARCHAR service_area_id "Identificador da área de serviço"
        VARCHAR region_name "Nome da região geográfica"
        VARCHAR densidade_populacional "Classificação de densidade populacional"
        VARCHAR classificacao_urbano_rural "Classificação urbano/rural"
        DECIMAL latitude "Coordenada geográfica - latitude"
        DECIMAL longitude "Coordenada geográfica - longitude"
    }

    DIM_PRESTADOR {
        BIGINT sk_prestador PK "Surrogate key"
        VARCHAR issuer_id UK "Identificador da seguradora"
        VARCHAR issuer_name "Nome da seguradora"
        VARCHAR network_id UK "Identificador da rede"
        VARCHAR network_name "Nome da rede de prestadores"
        VARCHAR network_tier "Nível da rede (Broad, Narrow, etc.)"
        VARCHAR network_url "URL da rede de prestadores"
        VARCHAR tipo_rede "Tipo da rede de prestadores"
        VARCHAR tamanho_rede "Classificação do tamanho da rede"
        DECIMAL score_qualidade "Score de qualidade da rede (0-100)"
    }

    DIM_BENEFICIOS {
        BIGINT sk_beneficios PK "Surrogate key"
        VARCHAR ehb_benefit_id UK "ID do benefício essencial de saúde"
        VARCHAR benefit_name "Nome do benefício"
        TEXT covered_text "Texto descritivo da cobertura"
        TEXT exclusions_text "Texto das exclusões"
        TEXT explanation_text "Texto explicativo do benefício"
        DECIMAL copay_amount "Valor do copagamento"
        DECIMAL coinsurance_rate "Taxa de cosseguro (0-1)"
        BOOLEAN subject_to_deductible_flag "Sujeito à franquia"
        VARCHAR categoria_beneficio "Categoria do benefício"
        INTEGER prioridade_beneficio "Prioridade do benefício (1-10)"
    }

    APOIO_CROSSWALK_PLANOS {
        BIGINT sk_crosswalk PK "Surrogate key"
        VARCHAR plan_id_original_2014 "ID original do plano em 2014"
        VARCHAR plan_id_original_2015 "ID original do plano em 2015"
        VARCHAR plan_id_original_2016 "ID original do plano em 2016"
        VARCHAR linhagem_plano_id FK "ID unificado da linhagem"
        VARCHAR issuer_id "ID da seguradora"
        VARCHAR tipo_mudanca "Tipo de mudança (CONTINUIDADE, FUSAO, CISAO, NOVO)"
        DECIMAL confidence_score "Grau de confiança do mapeamento (0-1)"
        DATE data_inicio_vigencia "Data de início da vigência"
        DATE data_fim_vigencia "Data de fim da vigência"
        BOOLEAN flag_ativo "Flag de atividade do mapeamento"
        TEXT observacoes "Observações sobre a regra aplicada"
    }
```

## Tables Description

### FATO_PLANOS_MERCADO_SAUDE (Fact Table)
**Purpose**: Central fact table containing quantitative measures for health insurance plans  
**Grain**: One health plan in a specific region during a specific time period  
**Type**: Transaction fact table with additive and semi-additive measures  
**Estimated Volume**: 2-3 million records (2014-2016), growing ~1M records/year  

**Primary Key**: Composite key (sk_plano, sk_tempo, sk_geografia)  
**Foreign Keys**: sk_tempo, sk_plano, sk_geografia, sk_prestador, sk_beneficios  

### DIM_TEMPO (Time Dimension)
**Purpose**: Temporal dimension with daily granularity and plan-specific hierarchies  
**Type**: Standard time dimension with plan year support  
**SCD Type**: Type 1 (no history tracking needed for time)  

**Primary Key**: sk_tempo (surrogate key)  
**Natural Key**: data_completa  

### DIM_PLANO (Plan Dimension)
**Purpose**: Central dimension for health insurance plans with temporal lineage support  
**Type**: Main dimension with crosswalk lineage implementation  
**SCD Type**: Type 2 (maintains history for plan changes)  

**Primary Key**: sk_plano (surrogate key)  
**Natural Keys**: plan_id_original, linhagem_plano_id  
**Foreign Key**: References DIM_PRESTADOR for primary provider  

### DIM_GEOGRAFIA (Geography Dimension)
**Purpose**: Geospatial dimension for territorial analysis and coverage desert identification  
**Type**: Geographic dimension with hierarchical structure  
**SCD Type**: Type 1 (geographic changes are rare)  

**Primary Key**: sk_geografia (surrogate key)  
**Natural Key**: Composite (state_code + county_fips + rating_area)  
**Spatial Support**: Includes latitude/longitude for geospatial analysis  

### DIM_PRESTADOR (Provider Dimension)
**Purpose**: Healthcare provider networks and insurers dimension  
**Type**: Organizational dimension  
**SCD Type**: Type 2 (maintains history for network changes)  

**Primary Key**: sk_prestador (surrogate key)  
**Natural Key**: Composite (issuer_id + network_id)  

### DIM_BENEFICIOS (Benefits Dimension)
**Purpose**: Specific benefits and coverage details dimension  
**Type**: Descriptive dimension for benefit analysis  
**SCD Type**: Type 1 (benefit definitions are relatively stable)  

**Primary Key**: sk_beneficios (surrogate key)  
**Natural Key**: ehb_benefit_id  

### APOIO_CROSSWALK_PLANOS (Crosswalk Support Table)
**Purpose**: Specialized table for managing temporal lineage between plan years  
**Type**: Bridge/Helper table for crosswalk implementation  
**Function**: Maps plan continuity across 2014-2016 periods  

**Primary Key**: sk_crosswalk (surrogate key)  
**Foreign Key**: linhagem_plano_id references DIM_PLANO  
**Relationship**: One lineage can span multiple plans across years  

## Relationships

- **FATO_PLANOS_MERCADO_SAUDE** has **many-to-one** relationships with all dimension tables
- **DIM_PLANO** has **many-to-one** relationship with **DIM_PRESTADOR** (primary provider)
- **APOIO_CROSSWALK_PLANOS** has **one-to-many** relationship with **DIM_PLANO** (via lineage)
- **Plan temporal lineage**: Managed through **linhagem_plano_id** across years (M:N controlled)

## Indexes Strategy

### FATO_PLANOS_MERCADO_SAUDE
- **PK_FATO_PLANOS**: Clustered index on (sk_plano, sk_tempo, sk_geografia)
- **IDX_FATO_TEMPO_PLANO**: Non-clustered on (sk_tempo, sk_plano)
- **IDX_FATO_GEOGRAFIA_RATES**: Covering index on sk_geografia including rate columns
- **IDX_FATO_CROSSWALK**: Non-clustered on (plan_id_original, sk_tempo)

### Dimension Tables
- **Primary Keys**: Clustered indexes on all surrogate keys
- **Natural Keys**: Unique non-clustered indexes on business keys
- **DIM_GEOGRAFIA**: Spatial index on (latitude, longitude)
- **DIM_PLANO**: Unique index on linhagem_plano_id for crosswalk integrity

## Data Quality Rules

1. **Referential Integrity**: All foreign keys must reference valid dimension records
2. **Crosswalk Integrity**: Each linhagem_plano_id must have valid confidence_score (0-1)
3. **Temporal Consistency**: Plan effective dates must align with time dimension
4. **Geographic Validation**: Coordinates must be within valid US boundaries
5. **Business Rules**: Individual rates ≤ family rates, deductibles ≤ out-of-pocket limits

## Usage Patterns

- **OLAP Queries**: Optimized for aggregations and drill-down operations
- **Temporal Analysis**: Supports year-over-year comparisons via crosswalk
- **Geospatial Analysis**: Enables coverage desert identification
- **Regulatory Reporting**: Maintains audit trail and data lineage
- **Predictive Analytics**: Provides base for medical inflation modeling
