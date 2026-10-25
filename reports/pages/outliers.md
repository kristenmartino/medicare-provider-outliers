---
title: Outlier Detection
---

**The triage shortlist** — providers ranked by how far they sit from their specialty-and-state peers on the metric you pick. A high score is a candidate to investigate, **not** a verdict.

This table contains the **top 1,000 extracted rows per metric**, ranked by absolute modified z-score with at least 30 observed peers. The six metrics have separate lists. Searching or sorting applies only to the selected extract; a missing provider is not evidence that they were unflagged or absent from the warehouse. Full per-NPI lookup is not implemented in this public app.

Pick a metric to query its bundled rows in your browser (DuckDB-WASM). Sort any column, or search the extract by provider, specialty, or state.

**What the columns mean** (full math + what a flag does *not* mean: [Methodology](/methodology)):

- **Modified z (MAD):** robust distance from the peer-group *median*, `0.6745 × (value − median) / MAD`. Flags at **|z| ≥ 3.5** — unitless, and genuinely huge on skewed spend (the top row's ~134,510 is not a typo).
- **Peer n:** providers in the same `(NPPES taxonomy × state)` peer group, floored at **n ≥ 30**.
- **Metric peer n:** how many of those peers have a value for the *selected* metric — a flag requires this ≥ 30, so no provider is scored against a thin median.
- **Value:** USD totals for `total_drug_cost` / `total_medicare_payment`, USD per claim for `avg_cost_per_claim`, counts for claims / services, and a percentage for `brand_cost_share` (stored as a 0–1 ratio).

```sql metrics
select distinct metric from medicare.tab2_outliers_top1000 order by metric
```

<Dropdown data={metrics} name=metric value=metric defaultValue="total_drug_cost" title="Metric"/>

```sql outliers
select
    provider_full_name,
    specialty,
    state,
    peer_group_n,
    peer_n_metric,
    metric_value,
    modified_z_score
from medicare.tab2_outliers_top1000
where metric = '${inputs.metric.value}'
order by abs(modified_z_score) desc
```

<DataTable data={outliers} search=true rows=15>
    <Column id=provider_full_name title="Provider"/>
    <Column id=specialty/>
    <Column id=state align=center/>
    <Column id=peer_group_n title="Peer n" fmt='#,##0'/>
    <Column id=peer_n_metric title="Metric peer n" fmt='#,##0'/>
    <Column id=metric_value title="Value" fmt={inputs.metric.value === 'brand_cost_share' ? '0.0%' : inputs.metric.value === 'avg_cost_per_claim' ? 'usd2' : ['total_drug_cost', 'total_medicare_payment'].includes(inputs.metric.value) ? 'usd0' : '#,##0'}/>
    <Column id=modified_z_score title="Modified z" fmt='#,##0.0'/>
</DataTable>

The top **`total_drug_cost`** row is an **Emergency Medicine provider in IL** — $84M in Part D drug cost against a peer-group median that puts the modified z near **134,510**. Facility-level attribution is one possible explanation for extreme totals, but this analysis does not establish the cause — see [Methodology](/methodology).

## Modified-z distribution — {inputs.metric.value}

The shape of the top-1,000 tail for the selected metric:

<Histogram data={outliers} x=modified_z_score title="Modified-z (top 1,000 for selected metric)"/>
