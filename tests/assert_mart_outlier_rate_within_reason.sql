/*
    Singular test: the overall MAD-flag rate in mart_provider_outliers must
    stay under 8%.

    On the current methodology and CY 2023 data with per-metric coverage
    gates active, the MAD flag rate is in the ~4-5% range. The 8% ceiling
    catches the regression modes worth catching:
      - Removing the per-metric floor pushes the rate sharply up
      - Replacing MAD with stddev (or shrinking mad_constant) pushes it up
      - A methodology change that widens peer-group definition pushes it up

    Earlier draft of this test used 10% as the threshold — too loose. A
    regression that doubled the flag rate to 9.9% would silently pass. 8%
    is tight enough to surface real changes while still leaving headroom
    for legitimate year-over-year drift.
*/

with stats as (
    select
        count(*)                                                                    as total,
        sum(case when is_outlier_any_mad then 1 else 0 end)                          as flagged_mad
    from {{ ref('mart_provider_outliers') }}
)

select
    total,
    flagged_mad,
    flagged_mad::float / nullif(total, 0)                                            as flag_rate
from stats
where flagged_mad::float / nullif(total, 0) >= 0.08
