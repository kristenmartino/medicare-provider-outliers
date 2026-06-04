---
title: Medicare Provider Outliers
description: Cost & volume outlier detection across 7M+ CMS providers
---

Provider cost & volume outliers across **7.06M** CMS Part D / Part B providers, scored within `(specialty × state)` peer groups using a robust **MAD modified z-score**. Modeled in dbt on Snowflake; this page is served static from committed extracts (no live warehouse).

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

## Top outliers by metric

Pick a metric — the table re-queries instantly in your browser (DuckDB-WASM, no server round-trip).

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

The top `total_drug_cost` row is **Rushdi Alul** (Emergency Medicine, IL) — $84M in Part D drug cost against a peer-group median that puts his modified z near **134,510**.

## Outlier rate by state

```sql states
select state, n_providers, flagged_mad, pct_flagged_mad
from medicare.tab4_state_aggregates
where state is not null and n_providers > 1000
order by pct_flagged_mad desc
limit 20
```

<BarChart data={states} x=state y=pct_flagged_mad title="MAD outlier rate by state (%) — top 20" swapXY=true/>
