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

MAD and standard deviation are noisy on small samples. With n < 30, a single high-cost prescriber can collapse the MAD to near-zero, and every other provider in that peer group will look like a 10-sigma outlier. The floor is enforced in [`int_provider__peer_group_stats`](../models/intermediate/int_provider__peer_group_stats.sql) and inherited downstream. 9,490 peer groups (of a theoretical ~865 taxonomies × 50 states) survive — about 22% — covering 7.06M of the 7.21M total providers.

## 3. The metrics

Six metrics, three from Part D and three from Part B, each scored independently:

| # | Source | Metric | Why it matters |
|---|---|---|---|
| 1 | Part D | `total_drug_cost` | Headline cost number |
| 2 | Part D | `part_d_total_claims` | Volume — distinguishes high-volume from high-unit-cost prescribers |
| 3 | Part D | `brand_cost_share` | Brand-vs-generic mix; high brand share with average volume can be the most defensible savings opportunity |
| 4 | Part D | `avg_cost_per_claim` | Per-script economics |
| 5 | Part B | `total_medicare_payment` | Headline Part B cost |
| 6 | Part B | `total_services` | Part B volume |

A provider is flagged if **any** of the six metrics fires (`is_outlier_any_mad`, `is_outlier_any_zscore`). The per-metric flags stay in the mart so the Hex notebook can filter to specific dimensions (e.g., "show me only providers flagged on brand_cost_share").

## 4. Z-score vs. modified z-score

Both are computed for every metric. The two are calibrated to flag at roughly comparable rates on a normal distribution — but Medicare cost distributions are heavily right-skewed, and the two methods diverge sharply on real data.

### Classical z-score

$$z = \frac{x - \mu}{\sigma}$$

Threshold: `|z| ≥ 2.0`

The mean and standard deviation are themselves dragged toward the right tail by the extreme prescribers we're trying to detect. The threshold becomes hard to clear, and the method under-flags. Across our 7.06M providers, **2.08%** are flagged by z-score.

### Modified z-score (MAD-based)

$$\tilde{z} = \frac{0.6745 \cdot (x - \tilde{x})}{\text{MAD}}$$

where $\tilde{x}$ is the peer-group median and $\text{MAD} = \text{median}(|x - \tilde{x}|)$.

Threshold: `|z̃| ≥ 3.5` ([Iglewicz & Hoaglin, 1993](https://www.itl.nist.gov/div898/handbook/eda/section3/eda35h.htm))

The constant $0.6745$ scales MAD so that, for a normal distribution, MAD-based z-scores are comparable to classical z-scores. On real (skewed) Medicare data the modified z-score is robust to the tail — the median doesn't budge, MAD stays a measure of typical deviation, and **5.37%** of providers flag. That higher rate is the *correct* answer for a right-skewed population: more providers genuinely deviate from typical.

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
- **Attribution oddities are common in CMS data.** Several top "Emergency Medicine" outliers with hundred-million-dollar Part D drug costs are likely facility-level prescribing aggregated to a single NPI, not a single physician personally writing scripts at that scale.
- **One year, one snapshot.** The current build covers data year 2023. Multi-year trends — a provider drifting outlier over time — are a natural next iteration.

## 6. Knobs

Tunable in the relevant model file with a single `{% set %}` change:

| Knob | File | Default |
|---|---|---|
| `peer_group_min_n` | `int_provider__peer_group_stats.sql` | 30 |
| `z_threshold` | `mart_provider_outliers.sql` | 2.0 |
| `mad_threshold` | `mart_provider_outliers.sql` | 3.5 |
| `mad_constant` | `mart_provider_outliers.sql` | 0.6745 |

If you re-tune, re-run `dbt build --select +mart_provider_outliers` and compare outputs against `analyses/peer_group_diagnostics.sql`.
