{{ config(materialized = 'table') }}

/*
    Part D fact table — one row per (NPI × year). Carries provider-level
    aggregated cost, volume, and brand-vs-generic shares; ready for direct
    consumption by Hex / BI without further joining.
*/

select
    npi,
    data_year,
    total_claims,
    total_30day_fills,
    total_drug_cost,
    total_day_supply,
    distinct_generics,
    distinct_brands,
    distinct_generics + distinct_brands                  as distinct_drugs_total,
    brand_claims,
    generic_claims,
    brand_drug_cost,
    generic_drug_cost,
    brand_claims_share,
    brand_cost_share,
    avg_cost_per_claim
from {{ ref('int_part_d__provider_annual') }}
