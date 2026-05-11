/*
    Diagnostic view over peer groups — useful when re-tuning thresholds or
    investigating why a particular specialty has an unusual flag rate.

    Columns: per peer group, the count of providers, median drug cost,
    flagged count, and flag rate.
*/

with by_peer_group as (
    select
        specialty,
        state,
        peer_group_n,
        median_drug_cost,
        mad_drug_cost,
        count(*)                                              as providers_in_mart,
        sum(case when is_outlier_any_mad     then 1 else 0 end) as flagged_mad,
        sum(case when is_outlier_any_zscore  then 1 else 0 end) as flagged_zscore
    from {{ ref('mart_provider_outliers') }}
    group by 1, 2, 3, 4, 5
),

with_rates as (
    select
        *,
        round(100.0 * flagged_mad    / providers_in_mart, 1) as pct_flagged_mad,
        round(100.0 * flagged_zscore / providers_in_mart, 1) as pct_flagged_zscore
    from by_peer_group
)

-- Flag-rate outliers: peer groups where >40% of providers fire, OR where MAD
-- is suspiciously small (= peers are all tightly bunched and any deviation
-- looks extreme)
select *
from with_rates
where pct_flagged_mad > 40
   or mad_drug_cost < 1
order by pct_flagged_mad desc
