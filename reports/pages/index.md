---
title: Medicare Provider Outliers
---

Provider cost and volume comparisons using **2023 Medicare Part B/D data** and the **April 2026 NPPES registry**. The mart contains **7,062,726 registry providers** in admitted `(NPPES taxonomy × state)` groups, including providers without a Part B or Part D observation. Modeled in dbt on Snowflake; this site serves committed extracts — no live warehouse.

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

<BigValue data={kpis} value=total_providers_in_mart title="Registry providers in mart" fmt='#,##0'/>
<BigValue data={kpis} value=flagged_mad title="MAD outliers" fmt='#,##0'/>
<BigValue data={kpis} value=pct_flagged_mad title="MAD outlier rate" fmt='0.00"%"'/>
<BigValue data={kpis} value=flagged_zscore title="z-score outliers" fmt='#,##0'/>
<BigValue data={kpis} value=pct_flagged_zscore title="z-score rate" fmt='0.00"%"'/>
<BigValue data={kpis} value=part_d_spend_b title="Part D spend ($B)" fmt='usd1'/>

## Coverage and denominator

The committed summary records **1,069,017 Part D prescribers** and **1,076,323 Part B providers** within the mart. These populations overlap; adding them does not give a distinct Medicare-provider count. Part D drug cost totals **$205.7B** and Part B payments **$69.8B** in this extract.

The headline flag rates divide by **all 7,062,726 mart rows**, including registry providers without observed Medicare activity. They are not rates among Medicare-active or metric-eligible providers, and they do not measure detection accuracy. A flag also requires at least 30 observed peers for its metric. State rates use the same all-mart-row basis within each state.

## How to explore the snapshot

The ranked table contains the top 1,000 extracted rows per metric; the provider view contains six selected examples. These controls search the bundled extracts, not the full warehouse. The [source documentation](https://github.com/kristenmartino/medicare-provider-outliers/blob/48b862ff6b216187dbad3d418e0911f60389d515/docs/data_sources.md) records the input vintages. Later registry taxonomy and location attributes classify 2023 utilization, so changes in those attributes can affect peer membership.

## Comparing two scoring rules

At the configured thresholds, MAD flags **5.23%** of mart rows and classical z-score flags **2.01%**. MAD uses the median and median absolute deviation, which are less sensitive to extreme values than the mean and standard deviation. The thresholds also differ: **3.5** for modified z and **2.0** for classical z. No labeled review establishes which rule finds more actionable cases, or either rule's false-positive rate. A larger flagged set does not establish better detection.

Explore:

- **[Outlier Detection](/outliers)** — top 1,000 extracted rows per metric
- **[Provider Drill-Down](/provider)** — six selected providers and their available peer observations
- **[Geography](/geography)** — outlier rate by state
- **[Methodology](/methodology)** — peer groups, z vs MAD, and what a flag does *not* mean
