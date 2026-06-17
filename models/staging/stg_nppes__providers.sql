{{ config(materialized = 'view') }}

/*
    Cleaned NPPES individual providers. The pre-filter (setup/02_filter_nppes.py)
    already restricted to entity_type_code = '1' and dropped deactivated NPIs,
    so this is a thin cleanup layer.
*/

with raw as (
    select * from {{ source('cms', 'nppes_npi') }}
),

renamed as (
    select
        npi,
        entity_type_code,
        provider_last_name,
        provider_first_name,
        provider_middle_name,
        provider_credentials,

        -- Standardize state/city/zip
        upper(trim(practice_state))      as practice_state,
        initcap(trim(practice_city))     as practice_city,
        left(trim(practice_zip), 5)      as practice_zip5,

        provider_sex_code,
        primary_taxonomy_code,

        -- Rough specialty rollup from the first 3 chars of the NUCC taxonomy code.
        -- Full hierarchy lives at https://www.nucc.org/. Common groupings:
        --   207, 208 = Allopathic & Osteopathic Physicians
        --   174     = Other Service Providers (PAs, etc.)
        --   363     = Physician Assistants & Advanced Practice Nursing
        --   333     = Suppliers
        case left(primary_taxonomy_code, 3)
            when '207' then 'Physician'
            when '208' then 'Physician'
            when '363' then 'Advanced Practice'
            when '174' then 'Other Service Provider'
            when '333' then 'Supplier'
            when '291' then 'Laboratory'
            when '171' then 'Other Service Provider'
            when '193' then 'Group'
            else 'Other'
        end                              as specialty_grouping,

        -- Dates kept as varchar through staging; intermediate models cast.
        enumeration_date                 as enumeration_date_raw,
        last_update_date                 as last_update_date_raw,

        _loaded_at                       as loaded_at
    from raw
)

select * from renamed
