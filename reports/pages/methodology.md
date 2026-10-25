---
title: Methodology
---

## The question

For each Medicare provider: are their cost and volume metrics within the range of normal variation for **providers of the same specialty practicing in the same state**? If not — by how much, and on which metrics? The output is a per-provider triage signal, **not** a deterministic judgment.

## The peer group

| Choice | Decision |
|---|---|
| Specialty | **NPPES `primary_taxonomy_code`** → NUCC display name (865 codes, not the coarse CMS specialty text) |
| Geography | **Practice state** (USPS) |
| Floor | **n ≥ 30 providers** per peer group |

The recorded switch from CMS specialty text to NPPES taxonomy split "Internal Medicine" into 28 subspecialties and changed its MAD-flag rate from 45% to 31.8%. That change does not establish a reduction in false positives. The **9,490** admitted groups contain **7,062,726 registry providers**, including providers without observed Part B/D activity. The `n ≥ 30` floor is a modeling choice, not a guarantee of stable estimates or clinically comparable peers.

## Source vintages and coverage

The build combines **2023 Medicare Part B/D utilization** with the **April 2026 NPPES registry**. Taxonomy comes from NPPES; practice state is preferred, with Medicare state fields as a fallback. Later registry attributes classify earlier utilization and can change peer membership. See the [pinned source documentation](https://github.com/kristenmartino/medicare-provider-outliers/blob/48b862ff6b216187dbad3d418e0911f60389d515/docs/data_sources.md).

The summary extract records **1,069,017 Part D prescribers** and **1,076,323 Part B providers** in the mart; those populations overlap. Headline flag rates divide by all mart rows, not just Medicare-active or metric-eligible providers. State rates likewise divide by all mart rows in each state. Missing metrics are not evidence of typical activity.

The public table bundles the top 1,000 rows per metric, and the provider selector contains six examples. Neither offers a full-mart search. No warehouse refresh or labeled detection evaluation was performed for this copy correction.

## Six metrics

Part D: `total_drug_cost`, `part_d_total_claims`, `brand_cost_share`, `avg_cost_per_claim`.
Part B: `total_medicare_payment`, `part_b_total_services`.

A provider flags if **any** metric fires. Each flag is gated on that metric's *own* peer coverage being ≥ 30, so no one is flagged against a median computed from a handful of observations.

## Classical z-score vs. modified z-score (MAD)

- **Classical z:** `(x − mean) / stddev`, threshold `|z| ≥ 2.0`; **2.01%** of mart rows flag.
- **Modified z (MAD):** `0.6745 × (x − median) / MAD`, threshold `|z̃| ≥ 3.5`; **5.23%** of mart rows flag. Median/MAD is less sensitive to extreme observations than mean/standard deviation, but skew and small or zero MAD can still produce large scores.

The scaling constant makes the score scales comparable under a normal-distribution assumption; it does not make the **2.0 and 3.5 cutoffs** equivalent. More flags do not demonstrate greater accuracy. No labeled review establishes actionable-case recall, false-positive rates, or an optimal method or threshold.

A z-score is a unitless number of (robust) standard deviations, not a percentage; it can be negative and very large (the top outlier's modified-z is ~134,510).

---

## What a flag does *not* mean

**"Outlier" is a statistical descriptor, not an allegation.** A flagged provider is one whose published 2023 metric sits > 3.5 modified-z from their peer-group median. That is **not** a claim of fraud, abuse, medically inappropriate practice, or a recommendation to audit.

Many legitimate patterns produce extreme scores:

- **Facility-level prescribing** attributed to one NPI is a possible explanation to investigate, not a pattern verified by these provider aggregates.
- Sub-specialists sitting in a generic taxonomy code.
- Providers serving unusually sick panels (oncology, transplant, advanced HIV care).

Every name comes from the **public NPPES registry**; every dollar from the **public CMS Provider Data Catalog**. No PHI, no claims-level data. If you cite a specific finding, quote the statistical descriptor — not a value judgment.

Full math and code: [github.com/kristenmartino/medicare-provider-outliers](https://github.com/kristenmartino/medicare-provider-outliers).
