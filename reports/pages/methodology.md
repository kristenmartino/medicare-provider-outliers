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

Switching from CMS specialty text to NPPES taxonomy split "Internal Medicine" into 28 subspecialties and dropped its MAD-flag rate from 45% → ~32% — Cardiology ($416k median Part D cost) and Hematology/Oncology ($1.1M) are clearly different populations from general IM ($97k). The `n ≥ 30` floor keeps MAD/σ stable on small samples; **9,490** peer groups survive, covering 7.06M of 7.21M providers.

## Six metrics

Part D: `total_drug_cost`, `part_d_total_claims`, `brand_cost_share`, `avg_cost_per_claim`.
Part B: `total_medicare_payment`, `part_b_total_services`.

A provider flags if **any** metric fires. Each flag is gated on that metric's *own* peer coverage being ≥ 30, so no one is flagged against a median computed from a handful of observations.

## Classical z-score vs. modified z-score (MAD)

- **Classical z:** `(x − mean) / stddev`, threshold `|z| ≥ 2.0`. The mean and σ are themselves dragged toward the right tail we're hunting, so it under-flags — **2.01%** of providers.
- **Modified z (MAD):** `0.6745 × (x − median) / MAD`, threshold `|z̃| ≥ 3.5` (Iglewicz & Hoaglin). The median doesn't budge and MAD stays a stable measure of typical deviation, so it flags **5.23%** — the correct answer for a right-skewed population.

A z-score is a unitless number of (robust) standard deviations, not a percentage; it can be negative and very large (the top outlier's modified-z is ~134,510).

---

## What a flag does *not* mean

**"Outlier" is a statistical descriptor, not an allegation.** A flagged provider is one whose published 2023 metric sits > 3.5 modified-z from their peer-group median. That is **not** a claim of fraud, abuse, medically inappropriate practice, or a recommendation to audit.

Many legitimate patterns produce extreme scores:

- A single attending NPI absorbing **facility-level prescribing** for billing (the dominant pattern in top Emergency-Medicine outliers).
- Sub-specialists sitting in a generic taxonomy code.
- Providers serving unusually sick panels (oncology, transplant, advanced HIV care).

Every name comes from the **public NPPES registry**; every dollar from the **public CMS Provider Data Catalog**. No PHI, no claims-level data. If you cite a specific finding, quote the statistical descriptor — not a value judgment.

Full math and code: [github.com/kristenmartino/medicare-provider-outliers](https://github.com/kristenmartino/medicare-provider-outliers).
