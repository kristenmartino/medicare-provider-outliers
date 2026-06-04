---
title: Provider Drill-Down
---

A curated set of high-profile outliers. (Full per-NPI lookup over all 7M providers is a live-warehouse feature; this static demo covers six headline cases.)

```sql providers
select provider_full_name, specialty, state, city,
       total_drug_cost, mz_drug_cost, part_d_total_claims, brand_cost_share,
       total_medicare_payment, peer_group_n
from medicare.tab3_demo_providers
order by mz_drug_cost desc
```

<Dropdown data={providers} name=who value=provider_full_name defaultValue="RUSHDI ALUL" title="Provider"/>

```sql selected
select * from medicare.tab3_demo_providers
where provider_full_name = '${inputs.who.value}'
```

**{selected[0].provider_full_name}** — {selected[0].specialty} · {selected[0].city}, {selected[0].state} · peer group n = {selected[0].peer_group_n}

<BigValue data={selected} value=total_drug_cost title="Part D drug cost" fmt='usd0'/>
<BigValue data={selected} value=mz_drug_cost title="Modified-z (drug cost)" fmt='#,##0.0'/>
<BigValue data={selected} value=part_d_total_claims title="Part D claims" fmt='#,##0'/>
<BigValue data={selected} value=brand_cost_share title="Brand cost share" fmt='0.0%'/>

## How extreme versus the peer group?

The selected provider's Part D drug cost against their `(specialty × state)` peer group, bucketed by cost band. Most peers cluster in the low bands; this provider sits alone in the far-right band — the extreme right-skew the MAD modified-z is designed to catch. (A plain linear histogram is unreadable here: ~all peers collapse into one bar near $0 while a lone outlier stretches the axis to tens of millions.)

```sql cost_bands
with peers as (
    select pd.value as cost
    from medicare.tab3_demo_peer_dist pd
    join medicare.tab3_demo_providers p on pd.demo_npi = p.npi
    where p.provider_full_name = '${inputs.who.value}' and pd.series = 'peer_group'
)
select
    case
        when cost < 1000 then '1 · <$1k'
        when cost < 10000 then '2 · $1k–10k'
        when cost < 100000 then '3 · $10k–100k'
        when cost < 1000000 then '4 · $100k–1M'
        when cost < 10000000 then '5 · $1M–10M'
        else '6 · ≥$10M'
    end as cost_band,
    count(*) as peer_count
from peers
group by cost_band
order by cost_band
```

<BarChart data={cost_bands} x=cost_band y=peer_count sort=false title="Peers by Part D drug-cost band" subtitle="selected provider's peer group"/>
