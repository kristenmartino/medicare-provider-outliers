---
title: Outlier Detection
---

Pick a metric — the table re-queries **instantly in your browser** (DuckDB-WASM, no server round-trip). Sort any column, or search by provider, specialty, or state.

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

The top **`total_drug_cost`** row is **Rushdi Alul** (Emergency Medicine, IL) — $84M in Part D drug cost against a peer-group median that puts his modified z near **134,510**. High Emergency-Medicine scores are typically facility-level prescribing aggregated to one attending NPI — see [Methodology](/methodology).

## Modified-z distribution — {inputs.metric.value}

The shape of the top-1,000 tail for the selected metric:

<Histogram data={outliers} x=modified_z_score title="Modified-z (top 1,000 for selected metric)"/>
