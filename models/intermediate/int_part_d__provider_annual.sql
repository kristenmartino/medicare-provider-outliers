{{ config(materialized = 'table') }}

/*
    Roll up Part D from (NPI × drug) to (NPI × year).
    Adds brand-vs-generic share metrics and an avg-cost-per-claim derived value.
    Suppressed-beneficiary-count rows are still included for cost/claim sums —
    only the beneficiary count itself is unreliable.
*/

with part_d as (
    select * from {{ ref('stg_part_d__prescriber_drug') }}
),

aggregated as (
    select
        npi,
        max(data_year)                                                             as data_year,

        -- Pick a representative specialty/geo for the prescriber (modal value
        -- across all the drug rows; max() is a cheap stand-in)
        max_by(prescriber_specialty_text, total_claims)                            as prescriber_specialty_text,
        max_by(prescriber_state,          total_claims)                            as prescriber_state,
        max_by(prescriber_city,           total_claims)                            as prescriber_city,

        -- Volume / cost
        sum(total_claims)                                                          as total_claims,
        sum(total_30day_fills)                                                     as total_30day_fills,
        sum(total_drug_cost)                                                       as total_drug_cost,
        sum(total_day_supply)                                                      as total_day_supply,

        -- Distinct drugs prescribed
        count(distinct generic_name)                                               as distinct_generics,
        count(distinct brand_name)                                                 as distinct_brands,

        -- Brand vs generic splits
        sum(case when drug_kind = 'brand'   then total_claims     else 0 end)      as brand_claims,
        sum(case when drug_kind = 'generic' then total_claims     else 0 end)      as generic_claims,
        sum(case when drug_kind = 'brand'   then total_drug_cost  else 0 end)      as brand_drug_cost,
        sum(case when drug_kind = 'generic' then total_drug_cost  else 0 end)      as generic_drug_cost
    from part_d
    where npi is not null
    group by npi
),

derived as (
    select
        *,
        -- Shares over the prescriber's full Part D book
        case when total_claims    > 0 then brand_claims    / total_claims    end   as brand_claims_share,
        case when total_drug_cost > 0 then brand_drug_cost / total_drug_cost end   as brand_cost_share,
        case when total_claims    > 0 then total_drug_cost / total_claims    end   as avg_cost_per_claim
    from aggregated
)

select * from derived
