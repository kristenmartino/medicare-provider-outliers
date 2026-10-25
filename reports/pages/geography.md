---
title: Geography
---

Recorded MAD flag rates and Medicare spend by the provider state assigned in the mart. **The rate denominator is every registry provider in that state's mart rows**, including providers without observed Part B/D activity. Differences can reflect Medicare participation, available metric coverage, taxonomy, and patient mix; this view does not isolate a geographic cause or identify where audits are warranted.

The input pairs 2023 Part B/D utilization with April 2026 NPPES attributes. NPPES practice state is preferred, with Medicare state fields as a fallback. The table includes two-character state/territory codes with more than 1,000 mart rows; the map displays supported US states.

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
    <Column id=n_providers title="Registry providers" fmt='#,##0'/>
    <Column id=flagged_mad title="MAD outliers" fmt='#,##0'/>
    <Column id=pct_flagged_mad title="MAD rate %" fmt='0.00'/>
    <Column id=total_part_d_spend title="Part D spend" fmt='usd0'/>
</DataTable>
