{{ config(materialized = 'table') }}

/*
    Unified provider profile — one row per NPI present in any of the three
    sources. The canonical specialty is the NUCC display name keyed off the
    NPPES primary_taxonomy_code, which is granular enough to split Internal
    Medicine into Cardiology / GI / Nephrology / etc.

    Specialty preference for the *display* name:
      1. NUCC display_name keyed off NPPES taxonomy
      2. CMS Part D prescriber_specialty_text
      3. CMS Part B provider_specialty_text
      4. NPPES coarse specialty grouping
      5. Literal "Unknown"

    Peer-group key (canonical_taxonomy_code) preference:
      1. NPPES primary_taxonomy_code
      2. NULL — providers without NPPES coverage are excluded from peer groups
         in the marts (they can't be reliably benchmarked against peers).

    State preference: NPPES practice_state → Part D → Part B.
*/

with all_npis as (
    select npi from {{ ref('stg_nppes__providers') }}
    union
    select npi from {{ ref('int_part_d__provider_annual') }}
    union
    select npi from {{ ref('int_part_b__provider_annual') }}
),

nppes  as (select * from {{ ref('stg_nppes__providers')        }}),
part_d as (select * from {{ ref('int_part_d__provider_annual') }}),
part_b as (select * from {{ ref('int_part_b__provider_annual') }}),
nucc   as (select * from {{ ref('nucc_taxonomy')               }}),

joined as (
    select
        a.npi,

        -- NPPES identity
        n.provider_first_name,
        n.provider_last_name,
        n.provider_credentials,
        n.provider_sex_code,

        -- NPPES taxonomy + NUCC mapping
        n.primary_taxonomy_code                                                    as taxonomy_code,
        t.grouping                                                                 as nucc_grouping,
        t.classification                                                           as nucc_classification,
        t.specialization                                                           as nucc_specialization,
        n.specialty_grouping                                                       as nppes_specialty_grouping,

        -- Canonical specialty (display)
        coalesce(
            t.display_name,
            nullif(trim(d.prescriber_specialty_text), ''),
            nullif(trim(b.provider_specialty_text),   ''),
            n.specialty_grouping,
            'Unknown'
        )                                                                          as specialty,

        -- Canonical taxonomy_code for peer grouping. Null when NPPES coverage
        -- is missing — those providers are excluded from the outlier mart.
        n.primary_taxonomy_code                                                    as canonical_taxonomy_code,

        -- Best-available state
        coalesce(
            nullif(n.practice_state, ''),
            nullif(d.prescriber_state, ''),
            nullif(b.provider_state,   '')
        )                                                                          as state,

        coalesce(
            n.practice_city,
            initcap(d.prescriber_city),
            initcap(b.provider_city)
        )                                                                          as city,
        n.practice_zip5,

        n.npi is not null                                                          as is_in_nppes,
        d.npi is not null                                                          as is_part_d_prescriber,
        b.npi is not null                                                          as is_part_b_provider
    from all_npis a
    left join nppes  n using (npi)
    left join part_d d using (npi)
    left join part_b b using (npi)
    left join nucc   t on n.primary_taxonomy_code = t.taxonomy_code
)

select * from joined
