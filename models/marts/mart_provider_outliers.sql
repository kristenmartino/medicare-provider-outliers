{{ config(materialized = 'table') }}

/*
    The headline mart — per-provider outlier flags within (specialty × state)
    peer groups. Computes both classical z-score (mean/stddev) and modified
    z-score (0.6745 * (x − median) / MAD), which is more robust to skew —
    critical here because Medicare cost distributions are heavily right-skewed.

    Default thresholds:
      |z_score|           >= 2.0   → outlier_zscore_flag
      |modified_z_score|  >= 3.5   → outlier_mad_flag   (Iglewicz & Hoaglin)

    is_outlier_any:   true if ANY metric flags via the MAD method (the default
                      narrative — robust, not biased by a few mega-prescribers
                      pulling the stddev up).

    Peer groups < 30 already excluded upstream in
    int_provider__peer_group_stats; this mart inherits that floor.
*/

{% set z_threshold   = 2.0 %}
{% set mad_threshold = 3.5 %}
{% set mad_constant  = 0.6745 %}

with provider as (
    select * from {{ ref('dim_provider') }}
),

part_d as (
    select * from {{ ref('fct_part_d_provider_year') }}
),

part_b as (
    select * from {{ ref('fct_part_b_provider_year') }}
),

peer as (
    select * from {{ ref('int_provider__peer_group_stats') }}
),

joined as (
    select
        p.npi,
        p.provider_full_name,
        p.specialty,
        p.state,
        p.city,
        p.part_d_prescriber_flag,
        p.part_b_provider_flag,

        -- Part D facts
        d.data_year                                                                as part_d_year,
        d.total_drug_cost,
        d.total_claims                                                             as part_d_total_claims,
        d.brand_cost_share,
        d.avg_cost_per_claim,

        -- Part B facts
        b.data_year                                                                as part_b_year,
        b.total_medicare_payment,
        b.total_services                                                           as part_b_total_services,

        -- Peer-group stats
        peer.n_providers                                                           as peer_group_n,

        peer.mean_drug_cost,
        peer.stddev_drug_cost,
        peer.median_drug_cost,
        peer.mad_drug_cost,

        peer.mean_part_d_claims,
        peer.stddev_part_d_claims,
        peer.median_part_d_claims,
        peer.mad_part_d_claims,

        peer.mean_brand_cost_share,
        peer.stddev_brand_cost_share,
        peer.median_brand_cost_share,
        peer.mad_brand_cost_share,

        peer.mean_avg_cost_per_claim,
        peer.stddev_avg_cost_per_claim,
        peer.median_avg_cost_per_claim,
        peer.mad_avg_cost_per_claim,

        peer.mean_part_b_payment,
        peer.stddev_part_b_payment,
        peer.median_part_b_payment,
        peer.mad_part_b_payment,

        peer.mean_part_b_services,
        peer.stddev_part_b_services,
        peer.median_part_b_services,
        peer.mad_part_b_services
    from provider p
    inner join peer
        on p.specialty = peer.specialty
        and p.state    = peer.state
    left join part_d d on p.npi = d.npi
    left join part_b b on p.npi = b.npi
),

scored as (
    select
        *,
        -- Classical z-score (mean / stddev)
        case when stddev_drug_cost          > 0 then (total_drug_cost          - mean_drug_cost)          / stddev_drug_cost          end as z_drug_cost,
        case when stddev_part_d_claims      > 0 then (part_d_total_claims      - mean_part_d_claims)      / stddev_part_d_claims      end as z_part_d_claims,
        case when stddev_brand_cost_share   > 0 then (brand_cost_share         - mean_brand_cost_share)   / stddev_brand_cost_share   end as z_brand_cost_share,
        case when stddev_avg_cost_per_claim > 0 then (avg_cost_per_claim       - mean_avg_cost_per_claim) / stddev_avg_cost_per_claim end as z_avg_cost_per_claim,
        case when stddev_part_b_payment     > 0 then (total_medicare_payment   - mean_part_b_payment)     / stddev_part_b_payment     end as z_part_b_payment,
        case when stddev_part_b_services    > 0 then (part_b_total_services    - mean_part_b_services)    / stddev_part_b_services    end as z_part_b_services,

        -- Modified z-score (MAD-based, robust to skew)
        case when mad_drug_cost          > 0 then {{ mad_constant }} * (total_drug_cost          - median_drug_cost)          / mad_drug_cost          end as mz_drug_cost,
        case when mad_part_d_claims      > 0 then {{ mad_constant }} * (part_d_total_claims      - median_part_d_claims)      / mad_part_d_claims      end as mz_part_d_claims,
        case when mad_brand_cost_share   > 0 then {{ mad_constant }} * (brand_cost_share         - median_brand_cost_share)   / mad_brand_cost_share   end as mz_brand_cost_share,
        case when mad_avg_cost_per_claim > 0 then {{ mad_constant }} * (avg_cost_per_claim       - median_avg_cost_per_claim) / mad_avg_cost_per_claim end as mz_avg_cost_per_claim,
        case when mad_part_b_payment     > 0 then {{ mad_constant }} * (total_medicare_payment   - median_part_b_payment)     / mad_part_b_payment     end as mz_part_b_payment,
        case when mad_part_b_services    > 0 then {{ mad_constant }} * (part_b_total_services    - median_part_b_services)    / mad_part_b_services    end as mz_part_b_services
    from joined
),

flagged as (
    select
        *,
        abs(z_drug_cost)          >= {{ z_threshold }}     as outlier_zscore_drug_cost,
        abs(z_part_d_claims)      >= {{ z_threshold }}     as outlier_zscore_part_d_claims,
        abs(z_brand_cost_share)   >= {{ z_threshold }}     as outlier_zscore_brand_cost_share,
        abs(z_avg_cost_per_claim) >= {{ z_threshold }}     as outlier_zscore_avg_cost_per_claim,
        abs(z_part_b_payment)     >= {{ z_threshold }}     as outlier_zscore_part_b_payment,
        abs(z_part_b_services)    >= {{ z_threshold }}     as outlier_zscore_part_b_services,

        abs(mz_drug_cost)          >= {{ mad_threshold }}   as outlier_mad_drug_cost,
        abs(mz_part_d_claims)      >= {{ mad_threshold }}   as outlier_mad_part_d_claims,
        abs(mz_brand_cost_share)   >= {{ mad_threshold }}   as outlier_mad_brand_cost_share,
        abs(mz_avg_cost_per_claim) >= {{ mad_threshold }}   as outlier_mad_avg_cost_per_claim,
        abs(mz_part_b_payment)     >= {{ mad_threshold }}   as outlier_mad_part_b_payment,
        abs(mz_part_b_services)    >= {{ mad_threshold }}   as outlier_mad_part_b_services
    from scored
)

select
    *,
    -- Composite flags — true if ANY metric flags via that method
    coalesce(outlier_mad_drug_cost,          false)
        or coalesce(outlier_mad_part_d_claims,      false)
        or coalesce(outlier_mad_brand_cost_share,   false)
        or coalesce(outlier_mad_avg_cost_per_claim, false)
        or coalesce(outlier_mad_part_b_payment,     false)
        or coalesce(outlier_mad_part_b_services,    false)                          as is_outlier_any_mad,

    coalesce(outlier_zscore_drug_cost,          false)
        or coalesce(outlier_zscore_part_d_claims,      false)
        or coalesce(outlier_zscore_brand_cost_share,   false)
        or coalesce(outlier_zscore_avg_cost_per_claim, false)
        or coalesce(outlier_zscore_part_b_payment,     false)
        or coalesce(outlier_zscore_part_b_services,    false)                       as is_outlier_any_zscore
from flagged
