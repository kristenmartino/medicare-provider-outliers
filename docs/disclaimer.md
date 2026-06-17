# Statistical disclaimer

The provider-outlier marts in this repository are a **statistical exercise** on **public CMS data**. Please read this disclaimer before interpreting or citing any specific finding.

## "Outlier" is not an allegation

A provider flagged by `mart_provider_outliers.is_outlier_any_mad` is one whose published 2023 Part D or Part B metrics fall more than 3.5 modified-z-scores from the median of their (NPPES taxonomy × state) peer group. That is a statement about a single number's position in a distribution. It is **not**:

- a claim of fraud, abuse, or improper billing;
- a claim of medically inappropriate practice;
- a claim about the provider's professional reputation;
- a substitute for the actual investigative tools (cluster analysis, beneficiary overlap, prescribing relationship graphs, on-the-ground audit) that public payers actually use to triage candidates.

Many legitimate, defensible patterns produce extreme outlier scores in this kind of analysis:

- A single attending NPI absorbing facility-level prescribing for billing purposes (the dominant pattern in the top Emergency-Medicine outliers — see [`docs/findings.md`](./findings.md) §1).
- Sub-specialists embedded in a high-cost specialty whose taxonomy code is missing or generic.
- Providers serving unusually sick patient panels (oncology, transplant, advanced HIV care).
- Practice consolidation where one NPI becomes the billing identity for a multi-physician group.

## Data sources are public

Every name attached to an NPI in this project comes from the **public NPPES NPI Registry**, where it has been published by the provider themselves under the registry's data-dissemination policy. Every dollar figure comes from the **public CMS Provider Data Catalog**, which CMS publishes precisely so that researchers and journalists can perform analyses like this one. No PHI, no de-identified claims-level data, and no restricted-use file is touched anywhere in the DAG.

CMS suppresses the beneficiary count for cells with fewer than 11 beneficiaries (per CMS policy); the staging layer preserves these rows and surfaces explicit suppression flags rather than dropping them — cost and claim totals remain valid.

## Use this responsibly

If you cite a specific finding — in a Loom walkthrough, blog post, LinkedIn writeup, or social media — please:

1. Quote the statistical descriptor (modified-z score, peer-group rank), not a value judgment.
2. Link back to this disclaimer.
3. Avoid headlines that imply intent, malpractice, or wrongdoing on the part of a specifically-named provider.
4. Acknowledge that journalists and CMS itself have published analyses of these same files; an outlier in our marts is also an outlier in those — but the framing matters.

## Methodology and reproduction

Full math is in [`docs/methodology.md`](./methodology.md). Code is at [github.com/kristenmartino/medicare-provider-outliers](https://github.com/kristenmartino/medicare-provider-outliers). All thresholds, peer-group definitions, and outlier flags are configurable in the dbt project — re-run with different choices to surface a different set of providers.
