# Findings — what the mart actually surfaces

Five analytical findings from `mart_provider_outliers` on **CY 2023** data. Each is reproducible from a single SQL query against the marts.

> All dollar figures are USD totals across the 2023 Medicare data year, summed over the providers that land in the mart (those with NPPES taxonomy coverage). Total Part D drug cost across the **1.07M** Part D prescribers in the mart = **$205.7B**; total Part B Medicare payment across the **1.08M** Part B physicians = **$69.8B** (from `tab1_overview_kpis`). The findings here surface the variation, not the aggregate.

---

## 1. Extreme provider totals require attribution review

Of the ~64,500 Emergency Medicine physicians in the mart, the median Part D drug cost is **$692** — Emergency doctors prescribe little outpatient pharmacy. But twelve providers in that specialty have **>$5M each**, and the maximum is **$84M (an Emergency Medicine provider in IL, modified-z = 134,510)**.

These totals warrant checking source rows, joins, taxonomy assignment, and attribution before drawing a clinical or billing conclusion. Facility-level aggregation is one hypothesis; it has not been established by this analysis. The reported maximum above is $84M, not hundreds of millions, and the specialty-specific query below does not establish a top-ten pattern across all specialties.

**Methodological implication:** outlier flags surface candidates for investigation, not adjudication. A follow-up could examine facility relationships and claim attribution using additional data. Neither a facility-volume feature nor a validated threshold for downweighting providers is implemented here.

```sql
select provider_full_name, specialty, state, total_drug_cost, mz_drug_cost
from {{ ref('mart_provider_outliers') }}
where outlier_mad_drug_cost and specialty ilike '%emergency medicine%'
order by mz_drug_cost desc nulls last limit 10;
```

---

## 2. Brand-cost-share gap under a fixed peer-median assumption

The recorded analysis sums each above-median provider's total drug cost multiplied by the difference between its brand-cost share and the peer-group median. It reports a **$24.4B arithmetic gap** under that fixed-baseline assumption. The recorded largest groups include Internal Medicine in California ($468M) and Physician Assistants in New York ($373M).

This is a cost-share comparison, not a substitution-cost model, an addressable market, or an upper bound on achievable savings. The input lacks patient-level indications, therapeutic alternatives, prices after a change, and outcomes. Moving a cost share to the peer median does not establish what treatment would change or what it would cost. The gap can organize follow-up questions; it does not establish a provider's intent, inappropriate prescribing, or a financial return.

See `analyses/brand_share_opportunity.sql` for the calculation. The figures remain the historical build's results; no warehouse rerun was performed for this correction.

---

## 3. NPPES taxonomy changes the recorded flag rate

The first iteration used CMS Medicare specialty text and grouped **116,056 providers under "Internal Medicine"**. Its recorded MAD flag rate was 45%. That group combined subspecialties with different cost baselines; no labeled review established which flags were false positives.

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

Switching the key to NPPES `primary_taxonomy_code` changed the recorded Internal Medicine MAD flag rate to **31.8%**. Peer definitions affect the result; the lower rate does not demonstrate a reduction in false positives. Neither taxonomy/state grouping nor the population floor establishes clinical comparability.

---

## 4. MAD vs. classical z-score: 2.6× more flags, by design

| Method | Threshold | Flagged providers | Rate |
|---|---|---|---|
| Classical z-score (mean/stddev) | \|z\| ≥ 2.0 | 141,766 | 2.01% |
| Modified z-score (median/MAD) | \|MAD-z\| ≥ 3.5 | 369,200 | 5.23% |

The score scales have a normal-distribution scaling relationship, but the chosen **2.0 and 3.5 thresholds differ**. Mean/standard deviation and median/MAD respond differently to extreme observations. These rates divide by all 7,062,726 registry mart rows, including providers without observed Part B/D activity; they are not detection accuracy or rates among eligible Medicare providers.

The public Evidence app uses MAD for its ranked extracts and exposes the recorded classical count for comparison. No labeled evaluation establishes actionable-case recall, false-positive rates, or an optimal method or threshold.

---

## 5. Recorded geographic flag-rate variation

| State | MAD-flag rate | Providers in mart |
|---|---|---|
| **MS** | **8.00%** | 37,783 |
| **AL** | **7.53%** | 64,279 |
| **TN** | **7.10%** | 120,885 |
| ... | ... | ... |
| **NV** | 2.88% | 95,546 |
| **AK** | 2.54% | 26,576 |
| **DC** | 2.11% | 43,885 |

These are descriptive state rates using all registry mart rows as the denominator. Differences can reflect Medicare participation, metric coverage, taxonomy, and patient mix. Grouping scores by taxonomy and state does not standardize the state's aggregate rate for those factors. This analysis neither isolates a geographic cause nor tests agreement with external health-disparity findings.

This is the kind of finding the headline mart enables without any further modeling. A natural Day-22+ project would join in CMS HRR (Hospital Referral Region) or HSA (Health Service Area) shapefiles for sub-state geography.

---

## What's *not* in here yet

- **Multi-year drift**: the build is 2023 only. A provider flagged this year who wasn't last year is a much stronger signal than a steady-state outlier. Day-22 work.
- **Disease-mix adjustment**: peer groups control for specialty and state but not for the patient case-mix actually served. Hierarchical Condition Category (HCC) risk-adjustment would refine the comparison.
- **Network effects**: prescribers with overlapping patient panels (visible in CMS shared-patient data) get pulled along by the high-cost prescribers they share patients with. Untangling that requires a graph layer.
