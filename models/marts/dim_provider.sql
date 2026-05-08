{{ config(materialized = 'table') }}

/*
    Provider dimension. One row per NPI present in any source. Same shape as
    int_provider__profile but with a couple of presentation-layer touches:
    a `provider_full_name` for display, and renaming `is_in_nppes` etc. to
    a cleaner `*_flag` form.
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
    primary_taxonomy_code,
    nppes_specialty_grouping,
    specialty,
    state,
    city,
    practice_zip5,
    is_in_nppes                                                                    as in_nppes_flag,
    is_part_d_prescriber                                                           as part_d_prescriber_flag,
    is_part_b_provider                                                             as part_b_provider_flag
from profile
