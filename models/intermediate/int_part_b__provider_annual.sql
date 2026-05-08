{{ config(materialized = 'table') }}

/*
    Roll up Part B from (NPI × HCPCS × place_of_service) to (NPI × year).
    Filters to individual rendering providers (entity code 'I') — organizations
    don't fit the specialty-peer-group analysis the marts perform.
*/

with part_b as (
    select * from {{ ref('stg_part_b__provider_service') }}
    where provider_entity_code = 'I'
),

aggregated as (
    select
        npi,
        max(data_year)                                                              as data_year,

        -- Representative specialty/geo
        max_by(provider_specialty_text, total_services)                             as provider_specialty_text,
        max_by(provider_state,          total_services)                             as provider_state,
        max_by(provider_city,           total_services)                             as provider_city,

        -- Volume metrics
        sum(total_services)                                                         as total_services,
        sum(total_beneficiaries)                                                    as total_beneficiaries_naive_sum,
        sum(total_bene_day_services)                                                as total_bene_day_services,
        count(distinct hcpcs_code)                                                  as distinct_hcpcs,

        -- Cost — weight per-service averages by total_services to get a totals
        -- proxy. (Submitted charges and Medicare payments aren't published as
        -- per-row totals; CMS publishes per-service averages.)
        sum(avg_submitted_charge             * total_services)                      as total_submitted_charges,
        sum(avg_medicare_allowed_amount      * total_services)                      as total_medicare_allowed,
        sum(avg_medicare_payment_amount      * total_services)                      as total_medicare_payment,
        sum(avg_medicare_standardized_amount * total_services)                      as total_medicare_standardized
    from part_b
    where npi is not null
    group by npi
),

derived as (
    select
        *,
        case when total_services > 0
             then total_medicare_payment / total_services
        end                                                                          as avg_medicare_payment_per_service,
        case when total_medicare_allowed > 0
             then total_medicare_payment / total_medicare_allowed
        end                                                                          as payment_to_allowed_ratio
    from aggregated
)

select * from derived
