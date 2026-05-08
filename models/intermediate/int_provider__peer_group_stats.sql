{{ config(materialized = 'table') }}

/*
    Peer-group statistics per (specialty × state) for the metrics that drive
    outlier detection: total drug cost, total claims, brand-cost share, avg
    cost per claim, total Medicare payment, total Part B services.

    MAD (median absolute deviation) is computed in two passes — Snowflake
    can't nest median() inside median() in a single aggregate, so we first
    broadcast each group's median via a window function, then aggregate the
    absolute deviations.

    Peer groups smaller than 30 are filtered out — small-sample MAD/z-score
    on tiny groups produces indefensible flags.
*/

{% set peer_group_min_n = 30 %}

with provider as (
    select * from {{ ref('int_provider__profile') }}
    where specialty is not null and state is not null
),

with_metrics as (
    select
        p.npi,
        p.specialty,
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

-- Pass 1: broadcast each peer group's median back onto every row so we can
-- compute |x − median(x)| in pass 2.
with_group_medians as (
    select
        *,
        median(total_drug_cost)        over (partition by specialty, state) as gm_drug_cost,
        median(part_d_total_claims)    over (partition by specialty, state) as gm_part_d_claims,
        median(brand_cost_share)       over (partition by specialty, state) as gm_brand_cost_share,
        median(avg_cost_per_claim)     over (partition by specialty, state) as gm_avg_cost_per_claim,
        median(total_medicare_payment) over (partition by specialty, state) as gm_part_b_payment,
        median(total_services)         over (partition by specialty, state) as gm_part_b_services
    from with_metrics
),

-- Pass 2: aggregate to per-peer-group stats including MAD
peer_group as (
    select
        specialty,
        state,
        count(*)                                                                    as n_providers,

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
    group by 1, 2
)

select *
from peer_group
where n_providers >= {{ peer_group_min_n }}
