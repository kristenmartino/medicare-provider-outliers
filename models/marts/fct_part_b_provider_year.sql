{{ config(materialized = 'table') }}

/*
    Part B fact table — one row per (NPI × year). Provider-level Part B service
    volumes and reconstructed cost totals (per-service avg × services, summed).
*/

select
    npi,
    data_year,
    total_services,
    total_beneficiaries_naive_sum,
    total_bene_day_services,
    distinct_hcpcs,
    total_submitted_charges,
    total_medicare_allowed,
    total_medicare_payment,
    total_medicare_standardized,
    avg_medicare_payment_per_service,
    payment_to_allowed_ratio
from {{ ref('int_part_b__provider_annual') }}
