{{ config(materialized = 'view') }}

/*
    Cleaned Part D prescriber × drug grain. Carries one row per (NPI × drug)
    for the given data year. CMS suppresses cells with <11 beneficiaries —
    those rows have tot_benes nulled (`*` in source) but other measures still
    populated, so we keep them and let the marts decide whether to use them.
*/

with raw as (
    select * from {{ source('cms', 'part_d_prescribers') }}
),

renamed as (
    select
        -- Identifiers
        prscrbr_npi                      as npi,
        prscrbr_last_org_name            as prescriber_last_org_name,
        prscrbr_first_name               as prescriber_first_name,
        prscrbr_city                     as prescriber_city,
        prscrbr_state_abrvtn             as prescriber_state,
        prscrbr_state_fips               as prescriber_state_fips,
        prscrbr_type                     as prescriber_specialty_text,

        -- Drug
        brnd_name                        as brand_name,
        gnrc_name                        as generic_name,
        case
            when nullif(trim(brnd_name), '') is null then null
            when upper(brnd_name) = upper(gnrc_name) then 'generic'
            else 'brand'
        end                              as drug_kind,

        -- Volume / cost (cast varchar → numeric; CMS already nulled '*' via load)
        try_cast(tot_clms        as integer)        as total_claims,
        try_cast(tot_30day_fills as numeric(18, 2)) as total_30day_fills,
        try_cast(tot_day_suply   as integer)        as total_day_supply,
        try_cast(tot_drug_cst    as numeric(18, 2)) as total_drug_cost,
        try_cast(tot_benes       as integer)        as total_beneficiaries,

        -- 65+ subset
        try_cast(ge65_tot_clms        as integer)        as ge65_total_claims,
        try_cast(ge65_tot_30day_fills as numeric(18, 2)) as ge65_total_30day_fills,
        try_cast(ge65_tot_drug_cst    as numeric(18, 2)) as ge65_total_drug_cost,
        try_cast(ge65_tot_day_suply   as integer)        as ge65_total_day_supply,
        try_cast(ge65_tot_benes       as integer)        as ge65_total_beneficiaries,

        -- Suppression flags
        ge65_sprsn_flag                  as ge65_suppression_flag,
        ge65_bene_sprsn_flag             as ge65_beneficiary_suppression_flag,
        case when tot_benes is null then true else false end as is_beneficiary_count_suppressed,

        -- Provenance
        2023                             as data_year,
        _loaded_at                       as loaded_at
    from raw
)

select * from renamed
