{{ config(materialized = 'view') }}

/*
    Cleaned Part B provider × service grain. One row per
    (NPI × HCPCS × place_of_service) for the data year.
*/

with raw as (
    select * from {{ source('cms', 'part_b_services') }}
),

renamed as (
    select
        -- Identifiers
        rndrng_npi                       as npi,
        rndrng_prvdr_last_org_name       as provider_last_org_name,
        rndrng_prvdr_first_name          as provider_first_name,
        rndrng_prvdr_mi                  as provider_middle_initial,
        rndrng_prvdr_crdntls             as provider_credentials,
        rndrng_prvdr_ent_cd              as provider_entity_code,
        rndrng_prvdr_city                as provider_city,
        rndrng_prvdr_state_abrvtn        as provider_state,
        rndrng_prvdr_state_fips          as provider_state_fips,
        rndrng_prvdr_zip5                as provider_zip5,
        rndrng_prvdr_ruca                as provider_ruca,
        rndrng_prvdr_ruca_desc           as provider_ruca_desc,
        rndrng_prvdr_cntry               as provider_country,
        rndrng_prvdr_type                as provider_specialty_text,
        rndrng_prvdr_mdcr_prtcptg_ind    as medicare_participating_ind,

        -- Service
        hcpcs_cd                         as hcpcs_code,
        hcpcs_desc                       as hcpcs_description,
        hcpcs_drug_ind                   as hcpcs_drug_indicator,
        place_of_srvc                    as place_of_service,

        -- Volume
        try_cast(tot_benes        as integer) as total_beneficiaries,
        try_cast(tot_srvcs        as integer) as total_services,
        try_cast(tot_bene_day_srvcs as integer) as total_bene_day_services,

        -- Cost (averages per service, all decimals)
        try_cast(avg_sbmtd_chrg     as numeric(18, 4)) as avg_submitted_charge,
        try_cast(avg_mdcr_alowd_amt as numeric(18, 4)) as avg_medicare_allowed_amount,
        try_cast(avg_mdcr_pymt_amt  as numeric(18, 4)) as avg_medicare_payment_amount,
        try_cast(avg_mdcr_stdzd_amt as numeric(18, 4)) as avg_medicare_standardized_amount,

        -- Provenance
        2023                             as data_year,
        _loaded_at                       as loaded_at
    from raw
)

select * from renamed
