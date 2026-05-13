/*
    Singular test: every row in mart_provider_outliers must carry peer_group_n >= 30.

    The n >= 30 floor is enforced by int_provider__peer_group_stats, and the
    inner join in mart_provider_outliers should propagate that — but if anyone
    ever changes the join type or pre-filter, a regression would silently flag
    providers in tiny peer groups with noisy MAD/stddev. This test makes that
    invariant explicit and continuously verified.
*/

select
    npi,
    specialty,
    state,
    peer_group_n
from {{ ref('mart_provider_outliers') }}
where peer_group_n < 30
