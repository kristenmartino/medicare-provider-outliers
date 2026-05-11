/*
    Top MAD outliers on total Part D drug cost.
    Run with: dbt compile -s top_outliers   then run the SQL in Snowsight.

    Useful for: spot-checking the mart, sanity-checking specific NPIs that show
    up in public reporting, or feeding the headline "find the most extreme
    prescribers" tab in the Hex notebook.
*/

with flagged as (
    select
        provider_full_name,
        specialty,
        state,
        city,
        total_drug_cost,
        median_drug_cost                                                   as peer_median,
        peer_group_n,
        mz_drug_cost                                                       as modified_z_score
    from {{ ref('mart_provider_outliers') }}
    where outlier_mad_drug_cost
      and total_drug_cost is not null
)

select *
from flagged
order by modified_z_score desc nulls last
limit 100
