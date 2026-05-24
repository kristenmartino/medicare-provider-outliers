{{ config(materialized = 'table') }}

/*
    Peer-group statistics per (taxonomy_code × state) for the six metrics
    that drive outlier detection. Switching the specialty key from CMS
    Medicare specialty text to NPPES taxonomy code shrinks the largest
    peer groups from >100k providers (e.g. "Internal Medicine") down to
    typically a few thousand (e.g. "Internal Medicine / Cardiology in
    California"), which is a far more defensible apples-to-apples baseline.

    MAD (median absolute deviation) is computed two-pass:
      1. Window-broadcast each peer group's median back onto every row
      2. Aggregate |x − median(x)| within the peer group

    n_providers vs per-metric counts:
        n_providers counts every NPI in the (taxonomy × state) cell,
        whether they prescribed Part D, billed Part B, or neither.
        n_part_d / n_part_b / n_brand_share_observed / n_avg_cost_per_claim_observed
        count only providers with a non-null value for that metric — i.e. the
        actual denominator used by the median/mean/stddev/MAD for that metric.

        mart_provider_outliers gates flag computation on the per-metric counts
        (>= 30), so a peer group that meets the union floor but has only 5
        actual Part D prescribers will not produce Part D outlier flags.

    Peer groups smaller than 30 providers (union population) are filtered out
    here as the first admission gate — anything below that has no chance of
    producing reliable per-metric statistics either.
*/

{% set peer_group_min_n = 30 %}

with provider as (
    select * from {{ ref('int_provider__profile') }}
    where canonical_taxonomy_code is not null
      and state                   is not null
),

with_metrics as (
    select
        p.npi,
        p.canonical_taxonomy_code,
        p.state,

        -- Part D
        d.total_drug_cost,
        d.total_claims                                                              as part_d_total_claims,
        d.brand_cost_share,
        d.avg_cost_per_claim,

        -- Part B
        b.total_medicare_payment,
        b.total_services
    from provider p
    left join {{ ref('int_part_d__provider_annual') }} d using (npi)
    left join {{ ref('int_part_b__provider_annual') }} b using (npi)
),

with_group_medians as (
    select
        *,
        median(total_drug_cost)        over (partition by canonical_taxonomy_code, state) as gm_drug_cost,
        median(part_d_total_claims)    over (partition by canonical_taxonomy_code, state) as gm_part_d_claims,
        median(brand_cost_share)       over (partition by canonical_taxonomy_code, state) as gm_brand_cost_share,
        median(avg_cost_per_claim)     over (partition by canonical_taxonomy_code, state) as gm_avg_cost_per_claim,
        median(total_medicare_payment) over (partition by canonical_taxonomy_code, state) as gm_part_b_payment,
        median(total_services)         over (partition by canonical_taxonomy_code, state) as gm_part_b_services
    from with_metrics
),

peer_group as (
    select
        canonical_taxonomy_code,
        state,

        -- Population counts
        count(*)                                                                    as n_providers,
        count(total_drug_cost)                                                      as n_part_d,
        count(total_medicare_payment)                                               as n_part_b,
        count(brand_cost_share)                                                     as n_brand_share_observed,
        count(avg_cost_per_claim)                                                   as n_avg_cost_per_claim_observed,

        -- Part D drug cost
        avg(total_drug_cost)                                                        as mean_drug_cost,
        stddev(total_drug_cost)                                                     as stddev_drug_cost,
        median(total_drug_cost)                                                     as median_drug_cost,
        median(abs(total_drug_cost - gm_drug_cost))                                 as mad_drug_cost,

        -- Part D claims
        avg(part_d_total_claims)                                                    as mean_part_d_claims,
        stddev(part_d_total_claims)                                                 as stddev_part_d_claims,
        median(part_d_total_claims)                                                 as median_part_d_claims,
        median(abs(part_d_total_claims - gm_part_d_claims))                         as mad_part_d_claims,

        -- Brand cost share
        avg(brand_cost_share)                                                       as mean_brand_cost_share,
        stddev(brand_cost_share)                                                    as stddev_brand_cost_share,
        median(brand_cost_share)                                                    as median_brand_cost_share,
        median(abs(brand_cost_share - gm_brand_cost_share))                         as mad_brand_cost_share,

        -- Avg cost per claim
        avg(avg_cost_per_claim)                                                     as mean_avg_cost_per_claim,
        stddev(avg_cost_per_claim)                                                  as stddev_avg_cost_per_claim,
        median(avg_cost_per_claim)                                                  as median_avg_cost_per_claim,
        median(abs(avg_cost_per_claim - gm_avg_cost_per_claim))                     as mad_avg_cost_per_claim,

        -- Part B payment
        avg(total_medicare_payment)                                                 as mean_part_b_payment,
        stddev(total_medicare_payment)                                              as stddev_part_b_payment,
        median(total_medicare_payment)                                              as median_part_b_payment,
        median(abs(total_medicare_payment - gm_part_b_payment))                     as mad_part_b_payment,

        -- Part B services
        avg(total_services)                                                         as mean_part_b_services,
        stddev(total_services)                                                      as stddev_part_b_services,
        median(total_services)                                                      as median_part_b_services,
        median(abs(total_services - gm_part_b_services))                            as mad_part_b_services
    from with_group_medians
    group by canonical_taxonomy_code, state
),

-- Attach a deterministic specialty display name from NUCC. Previously used
-- any_value(specialty) which is non-deterministic across rebuilds when the
-- underlying int_provider__profile.specialty differs across rows in the same
-- (taxonomy × state) cell.
with_specialty as (
    select
        pg.*,
        coalesce(t.display_name, pg.canonical_taxonomy_code)                        as specialty
    from peer_group pg
    left join {{ ref('nucc_taxonomy') }} t
      on pg.canonical_taxonomy_code = t.taxonomy_code
)

select *
from with_specialty
where n_providers >= {{ peer_group_min_n }}
