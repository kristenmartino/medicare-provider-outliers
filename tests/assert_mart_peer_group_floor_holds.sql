/*
    Singular test: every flag in mart_provider_outliers must respect the
    per-metric peer-coverage floor of n >= 30.

    This is the post-fix version of the original test, which only checked
    peer_group_n (the union population) — a peer group could meet that
    floor with very few actual Part D prescribers, and the original mart
    would silently flag providers against a thin median. The mart now gates
    each flag on the per-metric count, and this test enforces that
    invariant continuously.
*/

select
    npi,
    specialty,
    state,
    peer_group_n,
    peer_n_part_d,
    peer_n_part_b,
    peer_n_brand_share,
    peer_n_avg_cost_per_claim
from {{ ref('mart_provider_outliers') }}
where peer_group_n < 30
   or (outlier_mad_drug_cost          and peer_n_part_d              < 30)
   or (outlier_mad_part_d_claims      and peer_n_part_d              < 30)
   or (outlier_mad_brand_cost_share   and peer_n_brand_share         < 30)
   or (outlier_mad_avg_cost_per_claim and peer_n_avg_cost_per_claim  < 30)
   or (outlier_mad_part_b_payment     and peer_n_part_b              < 30)
   or (outlier_mad_part_b_services    and peer_n_part_b              < 30)
   or (outlier_zscore_drug_cost          and peer_n_part_d              < 30)
   or (outlier_zscore_part_d_claims      and peer_n_part_d              < 30)
   or (outlier_zscore_brand_cost_share   and peer_n_brand_share         < 30)
   or (outlier_zscore_avg_cost_per_claim and peer_n_avg_cost_per_claim  < 30)
   or (outlier_zscore_part_b_payment     and peer_n_part_b              < 30)
   or (outlier_zscore_part_b_services    and peer_n_part_b              < 30)
