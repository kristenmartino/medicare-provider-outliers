# Findings — what the mart actually surfaces

Five analytical findings from `mart_provider_outliers` on **CY 2023** data. Each is reproducible from a single SQL query against the marts.

> All dollar figures are USD totals across the 2023 Medicare data year. Total Part D drug cost across 1.10M prescribers = **$213B**. Total Part B Medicare payment across 1.11M physicians = **$73B**. The findings here surface the variation, not the aggregate.

---

## 1. The top "individual" outliers are facility billing in disguise

Of the ~64,500 Emergency Medicine physicians in the mart, the median Part D drug cost is **$692** — Emergency doctors prescribe little outpatient pharmacy. But twelve providers in that specialty have **>$5M each**, and the maximum is **$84M (an Emergency Medicine provider in IL, modified-z = 134,510)**.

The signal is consistent: every top-10 individual outlier across specialties is an Emergency Medicine physician with hundred-million-dollar Part D claims. Real outpatient pharmacy spend at that scale by a single ER doctor isn't credible — the pattern strongly suggests facility-level prescribing aggregated to an attending NPI for billing purposes.

**Methodological implication:** outlier flags surface candidates for investigation, not adjudication. A meaningful operationalization would join `mart_provider_outliers` to a "facility prescriber" feature derived from the share of distinct drugs a single NPI accounts for in their HCO, and downweight cases where one NPI sits on >0.5% of a facility's claim volume.

```sql
select provider_full_name, specialty, state, total_drug_cost, mz_drug_cost
from {{ ref('mart_provider_outliers') }}
where outlier_mad_drug_cost and specialty ilike '%emergency medicine%'
order by mz_drug_cost desc nulls last limit 10;
```

---

## 2. Brand-vs-generic substitution: $24B *theoretical* excess (and why "addressable" is the wrong word)

For each provider, compare their `brand_cost_share` to their peer-group median. Sum the *excess* — drug cost that would shift to generics if every above-median provider matched their peer median:

**$24.4 billion nationally**. Spread across 1.07M providers (about 11.5% of total Part D spend). The largest absolute opportunity is in **Internal Medicine in California ($468M)** and **Physician Assistants in New York ($373M)**.

That number is a defensible **upper bound on the search space**, not a realistic savings projection. Treating brand share as a free dial that can be turned down to median requires four assumptions that don't hold in clinical practice:

1. **Therapeutic substitutability.** A meaningful share of brand prescriptions are for drugs with no generic equivalent (recently-approved molecules, biologics with no biosimilar, narrow-therapeutic-index drugs where bioequivalence isn't a free swap). Those rows of the mart will look like "excess brand" but aren't.
2. **The peer median is a moving target.** Drag the right tail to median and the median itself shifts down. The $24B over-counts because it pretends the baseline is fixed.
3. **Patient-level continuity.** Patients stabilized on a brand formulation experience real harm from involuntary substitution in some drug classes (anticonvulsants, immunosuppressants, levothyroxine). Net cost should also include readmissions and emergency visits that we don't observe in this data.
4. **Causal attribution.** A provider with high brand share might be (a) prescribing more brand than peers would for the same patients — actionable; or (b) attracting a sicker patient panel that genuinely needs brand — not actionable. This dataset can't distinguish those.

What the number IS good for: ranking peer groups by where the *gap* is biggest, so a payer policy team or formulary committee knows where to start asking "what's driving this gap?" rather than "how do we eliminate it?" `analyses/brand_share_opportunity.sql` gives the per-(state × specialty) breakdown for that ranking use case.

```sql
-- See analyses/brand_share_opportunity.sql for the full per-(state × specialty)
-- breakdown. The headline number is a search-space size, not a savings target.
```

---

## 3. NPPES taxonomy peer-grouping cuts spurious flag rates ~30%

The first iteration of this project used CMS Medicare specialty text and lumped **116,056 providers under "Internal Medicine"** in one peer group. 45% of them flagged via MAD — clearly an over-flag, since the peer group mixed general internists with cardiologists, oncologists, and nephrologists who have wildly different cost baselines.

| Sub-specialty (NPPES taxonomy, CA) | n_providers | Median Part D drug cost |
|---|---|---|
| Internal Medicine (general) | 20,021 | **$97k** |
| Cardiovascular Disease | 2,253 | **$416k** |
| Gastroenterology | 1,711 | **$91k** |
| Hematology & Oncology | 1,285 | **$1.1M** |
| Nephrology | 1,148 | **$169k** |
| Pulmonary Disease | 885 | **$292k** |
| Endocrinology, Diabetes & Metabolism | 884 | **$642k** |
| Rheumatology | 707 | **$897k** |

Switching the peer-group key to NPPES `primary_taxonomy_code` (865 NUCC codes, mapped via the [`nucc_taxonomy`](../seeds/nucc_taxonomy.csv) seed) dropped the Internal Medicine MAD-flag rate to **31.8%** — still high, but defensible. The general lesson: a peer group is only useful as long as members face the same prescribing economics. Coarse buckets create false-positive outliers; granular buckets surface real ones.

---

## 4. MAD vs. classical z-score: 2.6× more flags, by design

| Method | Threshold | Flagged providers | Rate |
|---|---|---|---|
| Classical z-score (mean/stddev) | \|z\| ≥ 2.0 | 141,766 | 2.01% |
| Modified z-score (median/MAD) | \|MAD-z\| ≥ 3.5 | 369,200 | 5.23% |

The methods would flag at comparable rates on a normal distribution. They diverge sharply here because Medicare cost distributions are heavily right-skewed — the few mega-prescribers pull the mean toward themselves and inflate the stddev, making the z-score threshold hard to clear. MAD-based scoring uses the median and median absolute deviation, both robust to the right tail.

In a portfolio-quality outlier model on Medicare-style data, the MAD method is the right default. The mart exposes **both** scores so the Hex notebook can render the contrast and the analyst can pick the threshold that fits the use case (audit triage vs. broad scanning vs. headline-only flagging).

---

## 5. Geographic flag-rate variation tracks known health-disparity literature

| State | MAD-flag rate | Providers in mart |
|---|---|---|
| **MS** | **8.3%** | 37,783 |
| **AL** | **7.8%** | 64,279 |
| **TN** | **7.3%** | 120,885 |
| ... | ... | ... |
| **NV** | 3.0% | 95,546 |
| **AK** | 2.8% | 26,576 |
| **DC** | 2.5% | 43,885 |

States with higher MAD-flag rates are concentrated in the Southeast — a pattern consistent with the rural-health and Medicare-spending-variation literature (cf. [Dartmouth Atlas](https://www.dartmouthatlas.org/), CMS Geographic Variation reports). The peer-group key already controls for specialty mix; what's left is genuine geographic dispersion in prescribing intensity, brand-vs-generic mix, and service utilization.

This is the kind of finding the headline mart enables without any further modeling. A natural Day-22+ project would join in CMS HRR (Hospital Referral Region) or HSA (Health Service Area) shapefiles for sub-state geography.

---

## What's *not* in here yet

- **Multi-year drift**: the build is 2023 only. A provider flagged this year who wasn't last year is a much stronger signal than a steady-state outlier. Day-22 work.
- **Disease-mix adjustment**: peer groups control for specialty and state but not for the patient case-mix actually served. Hierarchical Condition Category (HCC) risk-adjustment would refine the comparison.
- **Network effects**: prescribers with overlapping patient panels (visible in CMS shared-patient data) get pulled along by the high-cost prescribers they share patients with. Untangling that requires a graph layer.
