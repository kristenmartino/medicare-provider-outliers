---
title: Outlier Detection
---

**The triage shortlist** — providers ranked by how far they sit from their specialty-and-state peers on the metric you pick. A high score is a candidate to investigate, **not** a verdict.

Pick a metric — the table re-queries **instantly in your browser** (DuckDB-WASM, no server round-trip). Sort any column, or search by provider, specialty, or state.

**What the columns mean** (full math + what a flag does *not* mean: [Methodology](/methodology)):

- **Modified z (MAD):** robust distance from the peer-group *median*, `0.6745 × (value − median) / MAD`. Flags at **|z| ≥ 3.5** — unitless, and genuinely huge on skewed spend (the top row's ~134,510 is not a typo).
- **Peer n:** providers in the same `(NPPES taxonomy × state)` peer group, floored at **n ≥ 30**.
- **Metric peer n:** how many of those peers have a value for the *selected* metric — a flag requires this ≥ 30, so no provider is scored against a thin median.
- **Value:** the selected metric — USD totals for `total_drug_cost` / `total_medicare_payment`, counts for claims / services, a 0–1 ratio for `brand_cost_share`.

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
    <Column id=metric_value title="Value" fmt='#,##0'/>
    <Column id=modified_z_score title="Modified z" fmt='#,##0.0'/>
</DataTable>

The top **`total_drug_cost`** row is an **Emergency Medicine provider in IL** — $84M in Part D drug cost against a peer-group median that puts the modified z near **134,510**. High Emergency-Medicine scores are typically facility-level prescribing aggregated to one attending NPI — see [Methodology](/methodology).

## Modified-z distribution — {inputs.metric.value}

The shape of the top-1,000 tail for the selected metric:

<Histogram data={outliers} x=modified_z_score title="Modified-z (top 1,000 for selected metric)"/>
