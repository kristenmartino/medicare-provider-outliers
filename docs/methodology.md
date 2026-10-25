# Methodology — provider outlier detection

This document spells out the statistical choices behind `mart_provider_outliers`. The summary in the [README](../README.md#methodology--provider-outliers) is the elevator pitch; this file is the audit trail.

## 1. The question

For each Medicare provider, are their cost and volume metrics within the range of normal variation for **providers of the same specialty practicing in the same state**? If not — by how much, and on which metrics?

The output is per-provider flags suitable for downstream review, not a deterministic "fraud" judgment. The mart surfaces deviation magnitude alongside the boolean flag so an analyst can sort and triage.

## 2. The peer group

| Choice | Decision |
|---|---|
| Specialty dimension | **NPPES `primary_taxonomy_code`** (mapped to NUCC display name via the [`nucc_taxonomy`](../seeds/nucc_taxonomy.csv) seed) |
| Geography dimension | **NPPES `practice_state`** (USPS abbreviation) |
| Floor | **n ≥ 30 providers** in the peer group |

### Why NPPES taxonomy and not CMS specialty text

CMS publishes a Medicare specialty label inside Part D and Part B, but it's coarse — all 116k self-identified "Internal Medicine" providers share a single value regardless of subspecialty. NPPES (the National Plan & Provider Enumeration System) requires every NPI holder to register a taxonomy from the [NUCC code set](https://www.nucc.org/), which is hierarchical and granular:

| NPPES code | NUCC display | National count |
|---|---|---|
| `207R00000X` | Internal Medicine Physician (general) | 172k |
| `207RC0000X` | Cardiovascular Disease Physician | 25k |
| `207RG0100X` | Gastroenterology Physician | 17k |
| `207RH0003X` | Hematology & Oncology Physician | 11k |
| `207RN0300X` | Nephrology Physician | 11k |

The first iteration of this project used CMS specialty text and produced a 45% MAD-flag rate inside "Internal Medicine." Switching to NPPES taxonomy dropped that to **31.8%** by separating the subspecialties — a Cardiology median Part D cost of **$416k** vs Hematology & Oncology at **$1.1M** vs general IM at **$97k** are clearly different populations.

### Why state (and not HRR or HSA or country)

State is a defensible proxy for the market a provider serves while staying coarse enough to keep most peer groups above the n ≥ 30 floor. Hospital Referral Regions (HRR) or Health Service Areas (HSA) are tighter market geographies but would shrink many peer groups below the floor; that's a future-iteration knob.

### Why the n ≥ 30 floor

The project uses a floor of 30 registry providers per taxonomy/state group, with a separate requirement of 30 observed peers for each flagged metric. This is a modeling choice, not a guarantee of stable MAD or standard deviation. Small or zero dispersion can still produce extreme or unavailable scores. The recorded build admits 9,490 groups with 7,062,726 registry providers, including those without observed Part B/D activity.

The build joins 2023 Part B/D utilization to April 2026 NPPES attributes. State prefers NPPES practice state, with Part D/B state fallbacks. Later taxonomy or location changes can affect the peers used to classify earlier utilization. The [source documentation](data_sources.md) records the vintages.

### Population and flag-rate denominators

The [committed summary](../reports/sources/medicare/tab1_overview_kpis.csv) records 1,069,017 Part D prescribers and 1,076,323 Part B providers within the mart. These populations overlap and cannot be added to produce a distinct active-provider count. Headline flag rates divide by **all 7,062,726 mart rows**, not Medicare-active or metric-eligible providers. State rates use every mart row assigned to each state. Missing Medicare observations must not be interpreted as typical activity. See [demo coverage](demo_coverage.md) for exact checks and public extract limits.

## 3. The metrics

Six metrics, four from Part D and two from Part B, each scored independently:

| # | Source | Metric | Why it matters |
|---|---|---|---|
| 1 | Part D | `total_drug_cost` | Headline cost number |
| 2 | Part D | `part_d_total_claims` | Volume — distinguishes high-volume from high-unit-cost prescribers |
| 3 | Part D | `brand_cost_share` | Brand-vs-generic cost mix; does not establish substitutability or savings |
| 4 | Part D | `avg_cost_per_claim` | Per-script economics |
| 5 | Part B | `total_medicare_payment` | Headline Part B cost |
| 6 | Part B | `total_services` | Part B volume |

A provider is flagged if **any** of the six metrics fires (`is_outlier_any_mad`, `is_outlier_any_zscore`). The per-metric flags stay in the mart so the Hex notebook can filter to specific dimensions (e.g., "show me only providers flagged on brand_cost_share").

## 4. Z-score vs. modified z-score

Both scores are computed for available metrics. The 0.6745 scaling constant aligns score scales under a normal-distribution assumption; it does not make the selected 2.0 and 3.5 thresholds equivalent. The rules have not been calibrated to a labeled review set or to equal false-positive rates.

### Classical z-score

$$z = \frac{x - \mu}{\sigma}$$

Threshold: `|z| ≥ 2.0`

Mean and standard deviation are sensitive to extreme observations. At the configured cutoff, **2.01%** (141,766) of all 7,062,726 mart rows flag. There is no labeled evaluation establishing how many actionable cases this rule misses.

### Modified z-score (MAD-based)

$$\tilde{z} = \frac{0.6745 \cdot (x - \tilde{x})}{\text{MAD}}$$

where $\tilde{x}$ is the peer-group median and $\text{MAD} = \text{median}(|x - \tilde{x}|)$.

Threshold: `|z̃| ≥ 3.5` ([Iglewicz & Hoaglin, 1993](https://www.itl.nist.gov/div898/handbook/eda/section3/eda35h.htm))

Median and MAD are less sensitive to extreme observations than mean and standard deviation. At the configured cutoff, **5.23%** (369,200) of all mart rows flag. This larger set does not establish better detection. Actionable-case recall, false-positive rates, and the preferred method or threshold remain unmeasured.

### The two-pass MAD computation

Snowflake (and most SQL dialects) can't nest `median()` inside `median()` in a single aggregate. The peer-group stats model uses a window function for the inner median:

```sql
-- Pass 1: broadcast each peer group's median onto every row
median(total_drug_cost) over (partition by taxonomy_code, state) as gm_drug_cost

-- Pass 2: aggregate the absolute deviations
median(abs(total_drug_cost - gm_drug_cost)) as mad_drug_cost
```

See [`int_provider__peer_group_stats.sql`](../models/intermediate/int_provider__peer_group_stats.sql).

## 5. What the flags do *not* tell you

- **Outlier ≠ wrongdoing.** A pediatric hematology-oncology specialist on the high end of drug cost for their peer group may be doing exactly the right thing.
- **Outlier ≠ a recommendation to audit.** The mart sorts providers by deviation; downstream review (clinical context, patient mix, attribution patterns) is required before any action.
- **Attribution is unresolved.** Extreme Part D totals do not identify their cause. Facility-level aggregation is a possible explanation requiring additional evidence; this mart cannot establish personal prescribing behavior or facility attribution.
- **One utilization year, later registry.** The current build uses 2023 utilization and the April 2026 NPPES snapshot. It does not establish multi-year utilization trends or a provider's 2023 registry attributes.

## 6. Knobs

Tunable in the relevant model file with a single `{% set %}` change:

| Knob | File | Default |
|---|---|---|
| `peer_group_min_n` | `int_provider__peer_group_stats.sql` | 30 |
| `z_threshold` | `mart_provider_outliers.sql` | 2.0 |
| `mad_threshold` | `mart_provider_outliers.sql` | 3.5 |
| `mad_constant` | `mart_provider_outliers.sql` | 0.6745 |

If you re-tune, re-run `dbt build --select +mart_provider_outliers` and compare outputs against `analyses/peer_group_diagnostics.sql`.
