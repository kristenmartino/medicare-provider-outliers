/*
    Singular test: the overall MAD-flag rate in mart_provider_outliers must
    stay under 10%.

    On the current methodology and CY 2023 data, the MAD flag rate is ~5.4%.
    A jump above 10% is a strong signal that something has changed in the
    threshold, peer-group definition, or the underlying MAD computation —
    most likely a regression that "lifted" thresholds by replacing MAD with
    stddev or by using a smaller mad_constant. This test catches that before
    the marts ship a misleading flagged-provider count to Hex.

    Threshold is generous (current real value is half of it) so the test
    won't false-fire on natural year-over-year drift.
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
where flagged_mad::float / nullif(total, 0) >= 0.10
