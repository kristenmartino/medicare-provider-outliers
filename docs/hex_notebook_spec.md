# Hex notebook spec

Tab-by-tab build plan for the [`mart_provider_outliers`](https://github.com/kristenmartino/medicare-provider-outliers/blob/main/models/marts/mart_provider_outliers.sql) explorer. Each tab section lists the Hex input variables, a ready-to-paste SQL cell, and the chart / widget recommendation.

> **Schema note.** The SQL below references `ANALYTICS.DBT_DEV_MARTS.*` because that's the dev-target schema dbt builds into with the current `profiles.yml`. If you eventually add a `prod` target whose schemas collapse to `marts` / `intermediate` (via a custom `generate_schema_name` macro), swap the prefix. For Hex's "Hobby" workspace there's no real downside to staying on the dev schema.

> **Offline / trial-expiry note.** Every SQL cell below re-queries Snowflake on each viewer interaction, so the published app's interactivity dies when the free-trial warehouse lapses (~2026-06-06). The small result set behind each interactive cell is pre-materialized to a committed CSV under [`docs/hex_data/`](./hex_data/) (via [`setup/06_extract_hex_static.py`](../setup/06_extract_hex_static.py)) so the app keeps working with **no live warehouse**. See [**Static / offline mode**](#static--offline-mode-surviving-snowflake-trial-expiry) for the rewired cells and fidelity notes — wire those in before you publish if the warehouse is near expiry.

## Connection setup

1. In Hex: **Data → Connections → New connection → Snowflake**.
2. Account: `jrc82992.us-east-1`
3. User: `KRISTENMARTINO`
4. Role: `ANALYST`
5. Warehouse: `DBT_XS_WH`
6. Database: `ANALYTICS`
7. **Authentication: key-pair** — paste the **contents** of `~/.snowflake/keys/dbt_rsa_key.p8` (everything between `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`, inclusive) into the "Private key" field. Same key dbt and the loader use.

Then **Test connection**. You should see "Connected" and a row count when you preview a table.

## Notebook layout

Five tabs. Tabs map to Hex **App tabs** (the published-view layout), not separate notebooks. Each section below maps to one tab.

---

### Tab 1 — Overview (KPIs + trend stub)

**Purpose:** open-the-app summary. Big-number tiles, one trend chart placeholder for when multi-year data lands.

**Hex input cells:** none (this is the dashboard's "home" view).

**SQL cell — Overview KPIs:**

```sql
select
    count(*)                                                    as total_providers_in_mart,
    count_if(part_d_prescriber_flag)                            as part_d_prescribers,
    count_if(part_b_provider_flag)                              as part_b_providers,
    count_if(is_outlier_any_mad)                                as flagged_mad,
    count_if(is_outlier_any_zscore)                             as flagged_zscore,
    round(100.0 * count_if(is_outlier_any_mad) / count(*), 2)   as pct_flagged_mad,
    round(100.0 * count_if(is_outlier_any_zscore) / count(*),2) as pct_flagged_zscore,
    round(sum(total_drug_cost), 0)                              as total_part_d_spend_usd,
    round(sum(total_medicare_payment), 0)                       as total_part_b_spend_usd
from analytics.dbt_dev_marts.mart_provider_outliers
```

**Widget:** the query returns **9** values; surface **7** as Single-value tiles — `total_providers_in_mart`, `flagged_mad`, `pct_flagged_mad`, `flagged_zscore`, `pct_flagged_zscore`, `total_part_d_spend_usd`, `total_part_b_spend_usd`. Format `*_usd` as currency, `pct_*` as percent. The two sub-population counts (`part_d_prescribers`, `part_b_providers`) are optional extra tiles, or fold them under tile 1 as a secondary value.

---

### Tab 2 — Outlier Detection (parameterized table)

**Purpose:** the interactive workhorse. Slider controls peer-relative threshold, filters narrow the population, ranked table is the output.

**Hex input cells:**

| Variable | Type | Default | Source |
|---|---|---|---|
| `specialty_filter` | Multi-select | (none = all) | `select distinct specialty from … order by 1` |
| `state_filter` | Multi-select | (none = all) | `select distinct state from … where state is not null order by 1` |
| `mad_threshold` | Numeric slider | 3.5 | min 1.0, max 10.0, step 0.5 |
| `metric` | Single-select | `total_drug_cost` | hardcoded options: `total_drug_cost`, `part_d_total_claims`, `brand_cost_share`, `avg_cost_per_claim`, `total_medicare_payment`, `part_b_total_services` |
| `min_peer_n` | Numeric input | 30 | min 30, max 1000, step 10 |

> **Hex Jinja conventions used below.** String inputs are bound as quoted parameters, so: reference a single-select with bare `{{metric}}` (Hex adds the quotes); inject a column *name* with `{{ metric | sqlsafe }}`; expand a multi-select into an `IN (…)` list with `{{ filter | array }}`; guard optional filters with `{% if filter %}`. Numeric inputs (`{{min_peer_n}}`, `{{mad_threshold}}`) interpolate unquoted. ([Hex: parameterize SQL](https://learn.hex.tech/tutorials/connect-to-data/parameterize-sql))

**SQL cell — Outlier table:**

```sql
select
    npi,
    provider_full_name,
    specialty,
    state,
    city,
    peer_group_n,
    -- per-metric peer coverage behind THIS metric's flag (mart gates on this, not the union count)
    case {{metric}}
        when 'total_drug_cost'        then peer_n_part_d
        when 'part_d_total_claims'    then peer_n_part_d
        when 'brand_cost_share'       then peer_n_brand_share
        when 'avg_cost_per_claim'     then peer_n_avg_cost_per_claim
        when 'total_medicare_payment' then peer_n_part_b
        when 'part_b_total_services'  then peer_n_part_b
    end                                                          as peer_n_metric,
    {{ metric | sqlsafe }}                                       as metric_value,
    case {{metric}}
        when 'total_drug_cost'        then mz_drug_cost
        when 'part_d_total_claims'    then mz_part_d_claims
        when 'brand_cost_share'       then mz_brand_cost_share
        when 'avg_cost_per_claim'     then mz_avg_cost_per_claim
        when 'total_medicare_payment' then mz_part_b_payment
        when 'part_b_total_services'  then mz_part_b_services
    end                                                          as modified_z_score
from analytics.dbt_dev_marts.mart_provider_outliers
where 1=1
  -- gate on the SELECTED metric's peer coverage, matching the mart's per-metric floor
  and case {{metric}}
        when 'total_drug_cost'        then peer_n_part_d
        when 'part_d_total_claims'    then peer_n_part_d
        when 'brand_cost_share'       then peer_n_brand_share
        when 'avg_cost_per_claim'     then peer_n_avg_cost_per_claim
        when 'total_medicare_payment' then peer_n_part_b
        when 'part_b_total_services'  then peer_n_part_b
      end >= {{min_peer_n}}
  {% if specialty_filter %}
    and specialty in ({{ specialty_filter | array }})
  {% endif %}
  {% if state_filter %}
    and state in ({{ state_filter | array }})
  {% endif %}
  and abs(
    case {{metric}}
        when 'total_drug_cost'        then mz_drug_cost
        when 'part_d_total_claims'    then mz_part_d_claims
        when 'brand_cost_share'       then mz_brand_cost_share
        when 'avg_cost_per_claim'     then mz_avg_cost_per_claim
        when 'total_medicare_payment' then mz_part_b_payment
        when 'part_b_total_services'  then mz_part_b_services
    end
  ) >= {{mad_threshold}}
order by abs(modified_z_score) desc nulls last
limit 1000
```

**Widget:** Hex **Table** cell sourced from this query. Configure conditional formatting on `modified_z_score`: red for ≥ 10, orange for 3.5–10, neutral below.

> **Why the per-metric gate:** `min_peer_n` filters on the coverage count *for the selected metric* (`peer_n_part_d` for the Part D metrics, `peer_n_part_b` for Part B, plus the brand-share and avg-cost-per-claim counts) — the same per-metric floor the mart applies when it sets `outlier_mad_*` ([mart_provider_outliers.sql](../models/marts/mart_provider_outliers.sql) lines 121–133). Gating on the union `peer_group_n` instead would let the slider surface a provider flagged against a median computed from only a handful of actual prescribers. `peer_n_metric` is in the table so the denominator behind every flag stays auditable.

---

### Tab 3 — Provider Drill-Down

**Purpose:** search-and-inspect for a specific NPI. Shows the provider's own metrics alongside their peer group's distribution.

**Hex input cells:**

| Variable | Type | Default | Notes |
|---|---|---|---|
| `search_npi` | Text input | (empty) | 10-digit NPI |
| `search_name` | Text input | (empty) | last-name fragment, used when `search_npi` is empty |

**SQL cell — Provider summary:**

```sql
with target as (
    select *
    from analytics.dbt_dev_marts.mart_provider_outliers
    where
        ({{search_npi}} != '' and npi = {{search_npi}})
        or
        ({{search_npi}} = ''
         and {{search_name}} != ''
         and upper(provider_full_name) like upper('%' || {{search_name}} || '%'))
)
select
    target.*,                       -- already includes taxonomy_code & specialty from the mart
    p.nucc_grouping,
    p.nucc_classification,
    p.nucc_specialization
from target
left join analytics.dbt_dev_marts.dim_provider p using (npi)
limit 25
```

**Widget:** Hex **Table** for the match list. When a single row is selected, a **Single-value grid** below can show: NPI, full name, taxonomy, peer-group-n, `total_drug_cost`, `mz_drug_cost`, `is_outlier_any_mad`.

**SQL cell — Peer distribution for the selected provider:**

```sql
with this_provider as (
    select specialty, state, total_drug_cost
    from analytics.dbt_dev_marts.mart_provider_outliers
    where npi = {{selected_npi}}   -- piped from the table selection; Hex binds the value (no manual quotes)
)
select
    'this_provider'                       as series,
    total_drug_cost                       as value
from this_provider
union all
select
    'peer_group'                          as series,
    mpo.total_drug_cost                   as value
from analytics.dbt_dev_marts.mart_provider_outliers mpo
join this_provider tp
  on mpo.specialty = tp.specialty
 and mpo.state     = tp.state
where mpo.total_drug_cost is not null
```

**Widget:** Hex **Histogram** with `series` mapped to a color, `value` on the x-axis. Add an annotation line at the median.

---

### Tab 4 — Geographic view (state choropleth)

**Purpose:** which states have the highest outlier rates and the highest absolute Medicare spend.

**Hex input cells:**

| Variable | Type | Default | Options |
|---|---|---|---|
| `geo_metric` | Single-select | `pct_flagged_mad` | `pct_flagged_mad`, `pct_flagged_zscore`, `total_part_d_spend`, `total_part_b_spend`, `n_providers` |

**SQL cell — State aggregates:**

```sql
select
    state,
    count(*)                                                      as n_providers,
    count_if(is_outlier_any_mad)                                  as flagged_mad,
    count_if(is_outlier_any_zscore)                               as flagged_zscore,
    round(100.0 * count_if(is_outlier_any_mad) / count(*), 2)     as pct_flagged_mad,
    round(100.0 * count_if(is_outlier_any_zscore) / count(*), 2)  as pct_flagged_zscore,
    round(sum(total_drug_cost), 0)                                as total_part_d_spend,
    round(sum(total_medicare_payment), 0)                         as total_part_b_spend
from analytics.dbt_dev_marts.mart_provider_outliers
where state is not null
group by state
order by state
```

**Widget:** Hex **Map** cell. Geography mode = "US States", join key = `state` column (USPS abbreviation), color scale = `{{geo_metric}}`. Hover tooltip = `n_providers`, `flagged_mad`, `pct_flagged_mad`, `total_part_d_spend`.

---

### Tab 5 — Methodology

**Purpose:** every reviewer asks "how was the threshold chosen?" Show your work.

**No SQL — Markdown cell.** Paste the body of [`docs/methodology.md`](./methodology.md) here, plus the disclaimer block from [`docs/disclaimer.md`](./disclaimer.md). Three sections:

1. **Peer-group key** — why NPPES taxonomy code, not CMS specialty text. Reference the Internal-Medicine breakdown table from `findings.md` §3.
2. **Z-score vs MAD** — the threshold math. Inline-quote the macro signatures from [`macros/outlier_detection.sql`](../macros/outlier_detection.sql).
3. **What an outlier flag means (and doesn't)** — link to `disclaimer.md`. End-of-tab so it's the last thing a viewer reads.

---

## Static / offline mode (surviving Snowflake trial expiry)

Hex caches each cell's **last run**, but any viewer interaction — the MAD slider, the metric / specialty / state filters, the NPI drill-down — **re-queries Snowflake**. When the free-trial warehouse lapses (~2026-06-06) those re-queries fail and the published app freezes on its cached output.

To keep the app interactive with **no live warehouse**, the small result set behind each interactive cell is pre-materialized to a committed CSV and the cell is rewired to read that CSV. Column names are preserved, so the **input cells, charts, and widgets are unchanged** — only each *query* cell's data source and body change (and the Tab-2 / Tab-3 bodies actually get *simpler*, because the per-metric `CASE` melt and the search are baked into the extract).

**Extracts** — generated by [`setup/06_extract_hex_static.py`](../setup/06_extract_hex_static.py) while the warehouse is live, committed under [`docs/hex_data/`](./hex_data/):

| File | Rows | Backs |
|---|---:|---|
| `tab1_overview_kpis.csv` | 1 | Tab 1 KPI tiles |
| `tab2_outliers_top1000.csv` | 6,000 | Tab 2 outlier table — top-1000 per metric × 6 metrics, per-metric peer floor (30) applied |
| `tab3_demo_providers.csv` | 6 | Tab 3 drill-down summary — curated demo NPIs |
| `tab3_demo_peer_dist.csv` | 6,978 | Tab 3 peer-distribution histogram — curated demo NPIs |
| `tab4_state_aggregates.csv` | 59 | Tab 4 state map |

Refresh any time the warehouse is live (idempotent, ~1 MB total output):

```bash
.venv/bin/python setup/06_extract_hex_static.py
```

### One-time wiring in Hex

1. **Get the CSVs into Hex.** Either **upload** them (most self-contained — **Data → Files → Upload** the five files from `docs/hex_data/`), or **read them from the published URL** (zero upload, auto-refreshes on `git push` — the Pages workflow serves `docs/` at `https://kristenmartino.github.io/medicare-provider-outliers/`, so each file is at `…/hex_data/<file>.csv`).
2. **Load them as dataframes** in one Python cell. Keep `npi` / `state` / `demo_npi` as strings — Tab 3's lookup and the map join rely on text keys:

```python
import pandas as pd
# BASE = "" when the CSVs are uploaded as Hex Files; otherwise the Pages URL prefix:
BASE = ""  # e.g. "https://kristenmartino.github.io/medicare-provider-outliers/hex_data/"
tab1           = pd.read_csv(BASE + "tab1_overview_kpis.csv")
tab2           = pd.read_csv(BASE + "tab2_outliers_top1000.csv", dtype={"npi": str})
tab3_providers = pd.read_csv(BASE + "tab3_demo_providers.csv",  dtype={"npi": str})
tab3_peer_dist = pd.read_csv(BASE + "tab3_demo_peer_dist.csv",  dtype={"demo_npi": str})
tab4           = pd.read_csv(BASE + "tab4_state_aggregates.csv", dtype={"state": str})
```

3. **Switch each query cell's source** from the Snowflake connection to **dataframe SQL** (Hex runs DuckDB over dataframes). The Jinja inputs (`{{metric}}`, `{{mad_threshold}}`, …) substitute exactly as in the live cells — the same Hex conventions noted under Tab 2 apply. Paste the bodies below.

### Tab 1 — Overview (dataframe `tab1`)

```sql
select * from tab1
```

Feeds the same seven Single-value tiles. **Fidelity: exact** — a frozen snapshot of the 1-row KPI query.

### Tab 2 — Outlier Detection (dataframe `tab2`)

The melt already collapsed the six per-metric `CASE` blocks into the `metric`, `peer_n_metric`, `metric_value`, and `modified_z_score` columns, so the offline cell is shorter than the live one. Input cells (`metric`, `mad_threshold`, `min_peer_n`) are unchanged:

```sql
select
    npi,
    provider_full_name,
    specialty,
    state,
    city,
    peer_group_n,
    peer_n_metric,
    metric_value,
    modified_z_score
from tab2
where metric = {{metric}}
  and peer_n_metric >= {{min_peer_n}}
  {% if specialty_filter %}
    and specialty in ({{ specialty_filter | array }})
  {% endif %}
  {% if state_filter %}
    and state in ({{ state_filter | array }})
  {% endif %}
  and abs(modified_z_score) >= {{mad_threshold}}
order by abs(modified_z_score) desc nulls last
limit 1000
```

Repoint the two filter dropdowns' **option queries** at the snapshot so every option yields rows:

- `specialty_filter` → `select distinct specialty from tab2 order by 1`
- `state_filter` → `select distinct state from tab2 order by 1`

**Fidelity:**

- **Metric switch + MAD slider — exact.** `tab2` is the top-1000 per metric by |modified-z| with the per-metric peer floor (30) applied. The 1000th-ranked |modified-z| is **34–739** across the six metrics — far above the slider's 10.0 ceiling — so with no specialty/state narrowing the offline table is **identical to the live query at every slider stop in [1.0, 10.0]**. *(Verified live Snowflake vs DuckDB-over-CSV: set-identical NPIs for 5 of 6 metrics; `brand_cost_share` differed by 2 rows at a tied |mz| = 34.43 boundary — immaterial.)*
- **specialty / state filters and `min_peer_n` > 30 — national-leaderboard semantics.** These narrow the national top-1000 rather than re-scanning all 7.06M providers, so a narrow slice can return few or zero rows. Example: no Internal-Medicine-in-NY provider appears, because that slice's most extreme drug-cost outlier sits at |mz| ≈ 62 while the national top-1000 cut is |mz| ≈ 739. This is honest and defensible — offline Tab 2 is *"the national outlier leaderboard, filtered,"* not *"the top 1,000 within an arbitrary subpopulation."* Raising `TOP_N` in the extractor does **not** fix it (even N = 10,000 leaves that slice empty); only a live warehouse can. Optional polish: a caption such as *"Offline mode ranks the 1,000 most extreme providers per metric nationwide; filters narrow this leaderboard."*

### Tab 3 — Provider Drill-Down (dataframes `tab3_providers`, `tab3_peer_dist`)

Free-text search over all 7M providers can't be shipped offline, so replace the `search_npi` / `search_name` text inputs with one **single-select `demo_npi`** over the curated top outliers (option query → `select npi from tab3_providers order by mz_drug_cost desc`; show `provider_full_name` as the label).

Provider summary cell:

```sql
select * from tab3_providers
where npi = {{demo_npi}}
```

Peer-distribution (histogram) cell:

```sql
select series, value
from tab3_peer_dist
where demo_npi = {{demo_npi}}
```

The histogram config (color by `series`, median annotation line) is unchanged.

The six pre-baked demo NPIs — the documented top drug-cost MAD outliers; the Emergency-Medicine cluster is the facility-billing pattern from [`findings.md`](./findings.md) §1 / [`disclaimer.md`](./disclaimer.md):

| NPI | Provider | Specialty | State | total_drug_cost | mz_drug_cost |
|---|---|---|---|---:|---:|
| 1649365529 | RUSHDI ALUL | Emergency Medicine | IL | $84.1M | 134,510 |
| 1578727327 | LINDSAY WEAVER | Emergency Medicine | IN | $44.8M | 50,241 |
| 1457435760 | SCOTT MURRAY | Emergency Medicine | IA | $24.8M | 35,728 |
| 1598712978 | MICHAEL BAZEL | Emergency Medicine | CA | $24.3M | 30,856 |
| 1538169388 | STEPHANIE HAN | Radiation Oncology | TX | $53.8M | 30,011 |
| 1457394306 | JUNG LEE | Surgery | NY | $9.5M | 16,126 |

**Fidelity: exact for these six NPIs** — each one's full peer distribution (same specialty × state, 175–3,707 peers) is materialized. *(Verified: offline peer counts match the live mart row-for-row.)* Free-text search of arbitrary providers stays live-only.

### Tab 4 — Geographic view (dataframe `tab4`)

```sql
select
    state,
    n_providers,
    flagged_mad,
    flagged_zscore,
    pct_flagged_mad,
    pct_flagged_zscore,
    total_part_d_spend,
    total_part_b_spend
from tab4
```

The map's `{{geo_metric}}` color selector is a client-side column pick over these columns — unchanged. **Fidelity: exact** — the full 59-state/territory aggregate; the summed `n_providers` reconciles to all 7,062,726 mart rows.

### Tab 5 — Methodology

Markdown only — no warehouse dependency, nothing to change.

### Fidelity at a glance

| Tab | Offline control | Fidelity vs live |
|---|---|---|
| 1 Overview | — | Exact |
| 2 Outliers | `metric`, `mad_threshold` | **Exact** across the full slider range |
| 2 Outliers | `specialty_filter` / `state_filter` / `min_peer_n` > 30 | Narrows the national top-1000 — slices may be sparse/empty by design |
| 3 Drill-down | `demo_npi` select | Exact for the 6 curated NPIs; free-text search is live-only |
| 4 Geographic | `geo_metric` | Exact |
| 5 Methodology | — | Exact (static) |

---

## Publish + share

1. **Save** in Hex → **Run all cells** to refresh against the latest mart.
2. **Publish** → **App** with the five tabs as your layout. Hex's free tier supports public links if your workspace is configured for it.
3. Copy the **published-app URL** into the project README under "What's next" → "Hex notebook" — replace the `[ ]` checkbox with `[x]` and the URL.
4. Take a screenshot of the Outlier-Detection tab with a clear flagged row for the README hero image.
