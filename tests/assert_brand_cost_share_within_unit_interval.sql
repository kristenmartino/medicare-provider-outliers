/*
    Singular test: brand_cost_share must be in [0, 1] (or null when total_drug_cost = 0).

    Catches arithmetic regressions in int_part_d__provider_annual.brand_cost_share —
    a value outside [0, 1] means brand_drug_cost > total_drug_cost (impossible by
    construction) or the wrong column landed in the wrong slot during a refactor.
*/

select
    npi,
    brand_cost_share
from {{ ref('int_part_d__provider_annual') }}
where brand_cost_share is not null
  and (brand_cost_share < 0 or brand_cost_share > 1)
