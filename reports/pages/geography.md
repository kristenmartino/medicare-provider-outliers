---
title: Geography
---

MAD outlier rate and Medicare spend by provider state — a regional lens for steering audit or reporting attention before drilling into specific peer groups. Outlier rates cluster in the South (MS, AL, TN), a pattern worth pairing with prescribing-norm and patient-mix context before reading anything into it.

```sql states
select
    state,
    n_providers,
    flagged_mad,
    pct_flagged_mad,
    total_part_d_spend
from medicare.tab4_state_aggregates
where state is not null and length(state) = 2 and n_providers > 1000
order by pct_flagged_mad desc
```

<USMap data={states} state=state value=pct_flagged_mad abbreviations=true title="MAD outlier rate by state (%)"/>

## Ranked by outlier rate

<DataTable data={states} search=true rows=12>
    <Column id=state align=center/>
    <Column id=n_providers title="Providers" fmt='#,##0'/>
    <Column id=flagged_mad title="MAD outliers" fmt='#,##0'/>
    <Column id=pct_flagged_mad title="MAD rate %" fmt='0.00'/>
    <Column id=total_part_d_spend title="Part D spend" fmt='usd0'/>
</DataTable>
