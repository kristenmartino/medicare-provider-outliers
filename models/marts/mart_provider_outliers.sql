{{ config(materialized = 'table') }}

/*
    Per-provider outlier flags within (taxonomy_code × state) peer groups.
    Computes both classical z-score (mean/stddev) and modified z-score
    (0.6745 × (x − median) / MAD), which is robust to right-skewed
    Medicare cost distributions.

    Thresholds: |z| ≥ 2.0, |modified-z| ≥ 3.5 (Iglewicz & Hoaglin).

    Per-metric coverage gates:
        A peer group can pass the n_providers >= 30 admission floor with only
        a handful of actual Part D prescribers — leaving Part D stats computed
        over a tiny subpopulation. To prevent flagging providers against a
        thin median, every flag is gated on the per-metric peer count being
        >= 30. peer_n_part_d gates the four Part D metrics; peer_n_part_b
        gates the two Part B metrics; brand-share and avg-cost-per-claim get
        their own per-metric counts because either can be null even when
        total_drug_cost is not (e.g. a provider with zero brand prescriptions
        has brand_cost_share = 0, not null, but providers with zero total
        cost have both null).

    is_outlier_any_mad / is_outlier_any_zscore:
        true if ANY of the six metrics flags via that method.

    Providers without NPPES coverage have no canonical_taxonomy_code and are
    excluded by the inner join with int_provider__peer_group_stats.
*/

{% set z_threshold       = 2.0 %}
{% set mad_threshold     = 3.5 %}
{% set per_metric_floor  = 30  %}

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
        p.taxonomy_code,
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

        -- Peer-group population counts
        peer.n_providers                                                           as peer_group_n,
        peer.n_part_d                                                              as peer_n_part_d,
        peer.n_part_b                                                              as peer_n_part_b,
        peer.n_brand_share_observed                                                as peer_n_brand_share,
        peer.n_avg_cost_per_claim_observed                                         as peer_n_avg_cost_per_claim,

        -- Peer-group statistics
        peer.mean_drug_cost,           peer.stddev_drug_cost,           peer.median_drug_cost,           peer.mad_drug_cost,
        peer.mean_part_d_claims,       peer.stddev_part_d_claims,       peer.median_part_d_claims,       peer.mad_part_d_claims,
        peer.mean_brand_cost_share,    peer.stddev_brand_cost_share,    peer.median_brand_cost_share,    peer.mad_brand_cost_share,
        peer.mean_avg_cost_per_claim,  peer.stddev_avg_cost_per_claim,  peer.median_avg_cost_per_claim,  peer.mad_avg_cost_per_claim,
        peer.mean_part_b_payment,      peer.stddev_part_b_payment,      peer.median_part_b_payment,      peer.mad_part_b_payment,
        peer.mean_part_b_services,     peer.stddev_part_b_services,     peer.median_part_b_services,     peer.mad_part_b_services
    from provider p
    inner join peer
        on p.taxonomy_code = peer.canonical_taxonomy_code
        and p.state        = peer.state
    left join part_d d on p.npi = d.npi
    left join part_b b on p.npi = b.npi
),

scored as (
    select
        *,
        -- Classical z-scores
        {{ zscore('total_drug_cost',        'mean_drug_cost',          'stddev_drug_cost')          }} as z_drug_cost,
        {{ zscore('part_d_total_claims',    'mean_part_d_claims',      'stddev_part_d_claims')      }} as z_part_d_claims,
        {{ zscore('brand_cost_share',       'mean_brand_cost_share',   'stddev_brand_cost_share')   }} as z_brand_cost_share,
        {{ zscore('avg_cost_per_claim',     'mean_avg_cost_per_claim', 'stddev_avg_cost_per_claim') }} as z_avg_cost_per_claim,
        {{ zscore('total_medicare_payment', 'mean_part_b_payment',     'stddev_part_b_payment')     }} as z_part_b_payment,
        {{ zscore('part_b_total_services',  'mean_part_b_services',    'stddev_part_b_services')    }} as z_part_b_services,

        -- Modified z-scores (MAD-based)
        {{ modified_zscore('total_drug_cost',        'median_drug_cost',          'mad_drug_cost')          }} as mz_drug_cost,
        {{ modified_zscore('part_d_total_claims',    'median_part_d_claims',      'mad_part_d_claims')      }} as mz_part_d_claims,
        {{ modified_zscore('brand_cost_share',       'median_brand_cost_share',   'mad_brand_cost_share')   }} as mz_brand_cost_share,
        {{ modified_zscore('avg_cost_per_claim',     'median_avg_cost_per_claim', 'mad_avg_cost_per_claim') }} as mz_avg_cost_per_claim,
        {{ modified_zscore('total_medicare_payment', 'median_part_b_payment',     'mad_part_b_payment')     }} as mz_part_b_payment,
        {{ modified_zscore('part_b_total_services',  'median_part_b_services',    'mad_part_b_services')    }} as mz_part_b_services
    from joined
),

flagged as (
    select
        *,
        -- Each flag is gated on per-metric peer coverage (>= 30) so we never
        -- flag a provider against a median computed from a tiny sub-population.
        ({{ is_outlier('z_drug_cost',          z_threshold) }} and peer_n_part_d              >= {{ per_metric_floor }}) as outlier_zscore_drug_cost,
        ({{ is_outlier('z_part_d_claims',      z_threshold) }} and peer_n_part_d              >= {{ per_metric_floor }}) as outlier_zscore_part_d_claims,
        ({{ is_outlier('z_brand_cost_share',   z_threshold) }} and peer_n_brand_share         >= {{ per_metric_floor }}) as outlier_zscore_brand_cost_share,
        ({{ is_outlier('z_avg_cost_per_claim', z_threshold) }} and peer_n_avg_cost_per_claim  >= {{ per_metric_floor }}) as outlier_zscore_avg_cost_per_claim,
        ({{ is_outlier('z_part_b_payment',     z_threshold) }} and peer_n_part_b              >= {{ per_metric_floor }}) as outlier_zscore_part_b_payment,
        ({{ is_outlier('z_part_b_services',    z_threshold) }} and peer_n_part_b              >= {{ per_metric_floor }}) as outlier_zscore_part_b_services,

        ({{ is_outlier('mz_drug_cost',          mad_threshold) }} and peer_n_part_d              >= {{ per_metric_floor }}) as outlier_mad_drug_cost,
        ({{ is_outlier('mz_part_d_claims',      mad_threshold) }} and peer_n_part_d              >= {{ per_metric_floor }}) as outlier_mad_part_d_claims,
        ({{ is_outlier('mz_brand_cost_share',   mad_threshold) }} and peer_n_brand_share         >= {{ per_metric_floor }}) as outlier_mad_brand_cost_share,
        ({{ is_outlier('mz_avg_cost_per_claim', mad_threshold) }} and peer_n_avg_cost_per_claim  >= {{ per_metric_floor }}) as outlier_mad_avg_cost_per_claim,
        ({{ is_outlier('mz_part_b_payment',     mad_threshold) }} and peer_n_part_b              >= {{ per_metric_floor }}) as outlier_mad_part_b_payment,
        ({{ is_outlier('mz_part_b_services',    mad_threshold) }} and peer_n_part_b              >= {{ per_metric_floor }}) as outlier_mad_part_b_services
    from scored
)

select
    *,
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
