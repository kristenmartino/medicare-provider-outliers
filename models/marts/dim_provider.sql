{{ config(materialized = 'table') }}

/*
    Provider dimension — one row per NPI seen in any source. Carries the
    granular NPPES taxonomy code (the peer-group key) plus the NUCC display
    name as `specialty`. Pass-through of int_provider__profile with
    display-friendly column names.
*/

with profile as (
    select * from {{ ref('int_provider__profile') }}
)

select
    npi,
    coalesce(
        nullif(trim(concat_ws(' ', provider_first_name, provider_last_name)), ''),
        npi
    )                                                                              as provider_full_name,
    provider_first_name,
    provider_last_name,
    provider_credentials,
    provider_sex_code,

    -- Specialty: NUCC display name + the underlying taxonomy code
    canonical_taxonomy_code                                                        as taxonomy_code,
    specialty,
    nucc_grouping,
    nucc_classification,
    nucc_specialization,
    nppes_specialty_grouping,

    -- Geography
    state,
    city,
    practice_zip5,

    -- Per-source coverage flags
    is_in_nppes                                                                    as in_nppes_flag,
    is_part_d_prescriber                                                           as part_d_prescriber_flag,
    is_part_b_provider                                                             as part_b_provider_flag
from profile
