---
title: Overview
---

# Medicare Provider Outliers

Cost & volume outlier detection across **7.06M** CMS Part D / Part B providers, scored within `(NPPES taxonomy × state)` peer groups using a robust **MAD modified z-score**. Modeled in dbt on Snowflake; this site is served static from committed extracts — no live warehouse.

```sql kpis
select
    total_providers_in_mart,
    flagged_mad,
    pct_flagged_mad,
    flagged_zscore,
    pct_flagged_zscore,
    total_part_d_spend_usd / 1e9 as part_d_spend_b
from medicare.tab1_overview_kpis
```

<BigValue data={kpis} value=total_providers_in_mart title="Providers analyzed" fmt='#,##0'/>
<BigValue data={kpis} value=flagged_mad title="MAD outliers" fmt='#,##0'/>
<BigValue data={kpis} value=pct_flagged_mad title="MAD outlier rate" fmt='0.00"%"'/>
<BigValue data={kpis} value=flagged_zscore title="z-score outliers" fmt='#,##0'/>
<BigValue data={kpis} value=pct_flagged_zscore title="z-score rate" fmt='0.00"%"'/>
<BigValue data={kpis} value=part_d_spend_b title="Part D spend ($B)" fmt='usd0.0'/>

## Robust beats classical on skewed cost data

The MAD method flags **5.23%** of providers versus the z-score's conservative **2.01%** — the right call for right-skewed Medicare spend, where the mean and standard deviation get dragged toward the very tails we're trying to detect.

Explore:

- **[Outlier Detection](/outliers)** — the parameterized, ranked outlier table
- **[Provider Drill-Down](/provider)** — a provider against their peer-group distribution
- **[Geography](/geography)** — outlier rate by state
- **[Methodology](/methodology)** — peer groups, z vs MAD, and what a flag does *not* mean
