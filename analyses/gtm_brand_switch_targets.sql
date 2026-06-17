/*
    GTM target list — "brand → generic / biosimilar substitution" sell.

    Commercial re-skin of analyses/brand_share_opportunity.sql: same excess-
    brand-cost math, but at PROVIDER grain so a sales / market-access team gets
    a ranked account list with a sized $ opportunity and a peer-benchmark
    talking point per row — rather than a (state x specialty) rollup.

    Same mart, interpretation flipped: the integrity read of a high-brand-share
    provider is "review"; the commercial read is "addressable spend, ranked."

    ICP: real Part D prescribers running a higher brand-cost mix than truly
    comparable peers (NPPES taxonomy x state, n >= 30), with enough absolute
    spend to be worth a rep's time.

    Run with: dbt compile -s gtm_brand_switch_targets   then run in Snowsight.
*/

with targets as (
    select
        npi,
        provider_full_name,
        specialty,
        state,
        city,
        total_drug_cost,
        brand_cost_share,
        median_brand_cost_share                                            as peer_median_brand_share,
        peer_n_brand_share,
        peer_group_n,
        mz_drug_cost
    from {{ ref('mart_provider_outliers') }}
    where part_d_prescriber_flag
      and brand_cost_share   is not null
      and peer_n_brand_share >= 30                          -- coverage: a real peer baseline
      and total_drug_cost    >= 250000                      -- worth pursuing
      and brand_cost_share - median_brand_cost_share >= 0.10   -- a clear 10+ point gap
      -- Artifact guardrail: drop the absurd right tail that findings.md #1 shows
      -- is facility billing aggregated to a single attending NPI, not a sellable
      -- prescriber. Heuristic placeholder for a proper share-of-facility-volume
      -- feature (see docs/findings.md ss1).
      and (mz_drug_cost is null or mz_drug_cost < 1000)
),

scored as (
    select
        *,
        brand_cost_share - peer_median_brand_share                         as brand_share_gap,
        (brand_cost_share - peer_median_brand_share) * total_drug_cost      as sized_opportunity_usd
    from targets
)

select
    case
        when sized_opportunity_usd >= 1000000 then 'Tier 1 (>=$1M)'
        when sized_opportunity_usd >=  250000 then 'Tier 2 ($250k-$1M)'
        else                                       'Tier 3 (<$250k)'
    end                                                                    as priority_tier,
    npi,
    provider_full_name,
    specialty,
    state,
    city,
    round(total_drug_cost)                                                 as total_drug_cost_usd,
    round(100 * brand_cost_share)                                          as brand_share_pct,
    round(100 * peer_median_brand_share)                                   as peer_median_pct,
    round(100 * brand_share_gap)                                           as gap_pts,
    round(sized_opportunity_usd)                                           as sized_opportunity_usd,
    peer_group_n,
    'Runs ' || round(100 * brand_cost_share) || '% brand vs a peer median of '
        || round(100 * peer_median_brand_share) || '% for ' || specialty || ' in ' || state
        || ' (n=' || peer_group_n || '). ~$' || round(sized_opportunity_usd)
        || ' shifts to lower-cost equivalents at peer mix.'                as talking_point
from scored
order by sized_opportunity_usd desc
limit 200
