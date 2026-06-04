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

The selected provider's Part D drug cost sits against the full distribution of their `(specialty × state)` peer group. The long right tail is exactly what the MAD modified-z is built to catch:

```sql peerdist
select pd.value as peer_drug_cost
from medicare.tab3_demo_peer_dist pd
join medicare.tab3_demo_providers p on pd.demo_npi = p.npi
where p.provider_full_name = '${inputs.who.value}' and pd.series = 'peer_group'
```

<Histogram data={peerdist} x=peer_drug_cost title="Peer-group Part D drug cost distribution"/>
