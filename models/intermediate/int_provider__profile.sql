{{ config(materialized = 'table') }}

/*
    Unified provider profile — one row per NPI present in any of the three
    sources. Picks the most informative specialty + state across NPPES, Part D,
    and Part B, with a fallback chain so coverage is maximal.

    Specialty preference:
      1. CMS-reported specialty from Part D (granular, ~80 specialties)
      2. CMS-reported specialty from Part B
      3. NPPES coarse specialty grouping

    State preference:
      1. NPPES practice state
      2. Part D prescriber state
      3. Part B provider state
*/

with all_npis as (
    select npi from {{ ref('stg_nppes__providers') }}
    union
    select npi from {{ ref('int_part_d__provider_annual') }}
    union
    select npi from {{ ref('int_part_b__provider_annual') }}
),

nppes as (
    select * from {{ ref('stg_nppes__providers') }}
),

part_d as (
    select * from {{ ref('int_part_d__provider_annual') }}
),

part_b as (
    select * from {{ ref('int_part_b__provider_annual') }}
),

joined as (
    select
        a.npi,

        -- NPPES identity
        n.provider_first_name,
        n.provider_last_name,
        n.provider_credentials,
        n.provider_sex_code,
        n.primary_taxonomy_code,
        n.specialty_grouping                                                        as nppes_specialty_grouping,

        -- Best-available specialty (from CMS files first, NPPES rollup last)
        coalesce(
            nullif(trim(d.prescriber_specialty_text), ''),
            nullif(trim(b.provider_specialty_text),   ''),
            n.specialty_grouping
        )                                                                            as specialty,

        -- Best-available state
        coalesce(
            nullif(n.practice_state, ''),
            nullif(d.prescriber_state, ''),
            nullif(b.provider_state,   '')
        )                                                                            as state,

        coalesce(
            n.practice_city,
            initcap(d.prescriber_city),
            initcap(b.provider_city)
        )                                                                            as city,

        n.practice_zip5,

        -- Coverage flags — useful both for lineage and for filtering downstream
        n.npi   is not null                                                          as is_in_nppes,
        d.npi   is not null                                                          as is_part_d_prescriber,
        b.npi   is not null                                                          as is_part_b_provider
    from all_npis a
    left join nppes  n using (npi)
    left join part_d d using (npi)
    left join part_b b using (npi)
)

select * from joined
