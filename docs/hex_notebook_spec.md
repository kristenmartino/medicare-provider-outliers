# Hex notebook spec

Tab-by-tab build plan for the [`mart_provider_outliers`](https://github.com/kristenmartino/medicare-provider-outliers/blob/main/models/marts/mart_provider_outliers.sql) explorer. Each tab section lists the Hex input variables, a ready-to-paste SQL cell, and the chart / widget recommendation.

> **Schema note.** The SQL below references `ANALYTICS.DBT_DEV_MARTS.*` because that's the dev-target schema dbt builds into with the current `profiles.yml`. If you eventually add a `prod` target whose schemas collapse to `marts` / `intermediate` (via a custom `generate_schema_name` macro), swap the prefix. For Hex's "Hobby" workspace there's no real downside to staying on the dev schema.

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

**Widget:** seven Hex "Single value" cells, one per metric. Format `*_usd` columns as currency, `pct_*` as percent.

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

**SQL cell — Outlier table (Hex Jinja-style):**

```sql
select
    npi,
    provider_full_name,
    specialty,
    state,
    city,
    peer_group_n,
    -- per-metric peer coverage behind THIS metric's flag (mart gates on this, not the union count)
    case '{{metric}}'
        when 'total_drug_cost'        then peer_n_part_d
        when 'part_d_total_claims'    then peer_n_part_d
        when 'brand_cost_share'       then peer_n_brand_share
        when 'avg_cost_per_claim'     then peer_n_avg_cost_per_claim
        when 'total_medicare_payment' then peer_n_part_b
        when 'part_b_total_services'  then peer_n_part_b
    end                                                          as peer_n_metric,
    {{metric}}                                                   as metric_value,
    case '{{metric}}'
        when 'total_drug_cost'        then mz_drug_cost
        when 'part_d_total_claims'    then mz_part_d_claims
        when 'brand_cost_share'       then mz_brand_cost_share
        when 'avg_cost_per_claim'     then mz_avg_cost_per_claim
        when 'total_medicare_payment' then mz_part_b_payment
        when 'part_b_total_services'  then mz_part_b_services
    end                                                          as modified_z_score
from analytics.dbt_dev_marts.mart_provider_outliers
where {{metric}} is not null
  -- gate on the SELECTED metric's peer coverage, matching the mart's per-metric floor
  and case '{{metric}}'
        when 'total_drug_cost'        then peer_n_part_d
        when 'part_d_total_claims'    then peer_n_part_d
        when 'brand_cost_share'       then peer_n_brand_share
        when 'avg_cost_per_claim'     then peer_n_avg_cost_per_claim
        when 'total_medicare_payment' then peer_n_part_b
        when 'part_b_total_services'  then peer_n_part_b
      end >= {{min_peer_n}}
  {% if specialty_filter|length %}
    and specialty in ({{specialty_filter | inclause}})
  {% endif %}
  {% if state_filter|length %}
    and state in ({{state_filter | inclause}})
  {% endif %}
  and abs(
    case '{{metric}}'
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
        ('{{search_npi}}' != '' and npi = '{{search_npi}}')
        or
        ('{{search_npi}}' = ''
         and '{{search_name}}' != ''
         and upper(provider_full_name) like upper('%' || '{{search_name}}' || '%'))
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
    where npi = '{{selected_npi}}'   -- piped from the table selection (npi is varchar)
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

## Publish + share

1. **Save** in Hex → **Run all cells** to refresh against the latest mart.
2. **Publish** → **App** with the five tabs as your layout. Hex's free tier supports public links if your workspace is configured for it.
3. Copy the **published-app URL** into the project README under "What's next" → "Hex notebook" — replace the `[ ]` checkbox with `[x]` and the URL.
4. Take a screenshot of the Outlier-Detection tab with a clear flagged row for the README hero image.
