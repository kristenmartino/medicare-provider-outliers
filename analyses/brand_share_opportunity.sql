/*
    Where is the brand-vs-generic prescribing gap biggest?
    Per (state × specialty), compare each provider's brand_cost_share to the
    peer-group median. Sum the *excess* brand cost — i.e., how much could be
    saved if outlier providers prescribed at peer-median brand mix.

    Sized down to the top 100 specialty × state cells for readability;
    Hex can repaginate.
*/

with provider as (
    select
        npi,
        specialty,
        state,
        total_drug_cost,
        brand_cost_share,
        median_brand_cost_share                                            as peer_median_brand_share
    from {{ ref('mart_provider_outliers') }}
    where brand_cost_share is not null
),

per_provider_excess as (
    select
        *,
        case
            when brand_cost_share > peer_median_brand_share
            then (brand_cost_share - peer_median_brand_share) * total_drug_cost
            else 0
        end                                                                as excess_brand_cost
    from provider
),

aggregated as (
    select
        specialty,
        state,
        count(*)                                                           as providers,
        sum(excess_brand_cost)                                             as total_excess_brand_cost,
        round(avg(brand_cost_share), 3)                                    as avg_brand_share,
        round(avg(peer_median_brand_share), 3)                             as peer_median_brand_share
    from per_provider_excess
    group by 1, 2
    having count(*) >= 30
)

select *
from aggregated
order by total_excess_brand_cost desc
limit 100
