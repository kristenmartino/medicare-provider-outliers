# Public demo coverage and interpretation

Checked October 25, 2026 against the committed extracts and extraction SQL at
`48b862ff6b216187dbad3d418e0911f60389d515`. This check did not connect to
Snowflake, refresh data, or evaluate detection accuracy.

## What the public application contains

| Surface | Bundled input | Coverage |
|---|---|---|
| Overview | `tab1_overview_kpis.csv` | One aggregate row |
| Outlier table | `tab2_outliers_top1000.csv` | 1,000 selected rows for each of six metrics |
| Provider selector | `tab3_demo_providers.csv` | Six selected examples |
| Cost-band chart | `tab3_demo_peer_dist.csv` | 6,978 rows, including six selected-provider rows and available peer cost observations |
| State comparison | `tab4_state_aggregates.csv` | 59 state/territory codes before the page's display filter |

These CSVs are under `reports/sources/medicare/`. The corresponding original
extract manifest is `docs/hex_data/README.md`, dated June 3, 2026. The Hex
specification is a mockup; Evidence is the public implementation. Search and
sort operate within the selected bundled extract. Full-mart or arbitrary-NPI
lookup is not implemented in this public application.

## Metric display

The ranked table formats brand-cost share as a percentage, average cost per
claim as USD with two decimals, cost/payment totals as USD, and claims/services
as counts. For example, the stored brand-cost share `0.23713651` must display
as **23.7%**, rather than rounding to the integer `0`. This changes display
formatting only; underlying values and sort order remain numeric.

## Denominator reconciliation

`setup/06_extract_hex_static.py::tab1_sql` uses `count(*)` across the mart as
the headline flag-rate denominator. The mart admits taxonomy/state groups with
at least 30 registry providers and retains their providers even when Part B/D
facts are missing. It separately requires 30 observed peers for a metric to
produce a flag.

| Recorded field | Value |
|---|---:|
| All registry providers in the mart | 7,062,726 |
| Part D prescriber flag | 1,069,017 |
| Part B provider flag | 1,076,323 |
| MAD flags | 369,200 / 7,062,726 = 5.23% rounded |
| Classical z flags | 141,766 / 7,062,726 = 2.01% rounded |
| Part D drug cost | $205,710,459,807 |
| Part B payments | $69,786,169,161 |

The Part B and Part D populations overlap. The aggregate does not provide their
distinct union or metric-eligible denominators; this correction does not invent
replacement active-provider flag rates. State rates also divide by all mart rows
in the state. A missing Medicare observation is not a typical or verified-normal
result.

The source vintages are 2023 Part B/D utilization and April 2026 NPPES. Later
taxonomy and location attributes can change the peer assignment of earlier
utilization. The project uses a classical cutoff of 2.0 and a modified-z cutoff
of 3.5; these are different thresholds. Flag counts do not measure false-positive
rates or actionable-case recall. No labeled evaluation establishes a preferred
rule.

## Reproduce the extract checks without a warehouse

Run from the repository root with Python's standard library:

```python
import csv
from collections import Counter
from decimal import Decimal
from pathlib import Path

root = Path("reports/sources/medicare")
def rows(name):
    with (root / name).open(newline="") as source:
        return list(csv.DictReader(source))

kpi, = rows("tab1_overview_kpis.csv")
assert int(kpi["total_providers_in_mart"]) == 7_062_726
assert int(kpi["part_d_prescribers"]) == 1_069_017
assert int(kpi["part_b_providers"]) == 1_076_323
for count, rate in [("flagged_mad", "pct_flagged_mad"),
                    ("flagged_zscore", "pct_flagged_zscore")]:
    calculated = 100 * Decimal(kpi[count]) / Decimal(kpi["total_providers_in_mart"])
    assert calculated.quantize(Decimal("0.01")) == Decimal(kpi[rate])

counts = Counter(row["metric"] for row in rows("tab2_outliers_top1000.csv"))
assert len(counts) == 6 and set(counts.values()) == {1000}
assert len(rows("tab3_demo_providers.csv")) == 6
assert len(rows("tab3_demo_peer_dist.csv")) == 6978
assert len(rows("tab4_state_aggregates.csv")) == 59
print("Committed extract coverage and headline denominators reconcile.")
```

Build the application with `cd reports && npm ci && npm run sources && npm run
build`. This exercises the bundled data and Evidence pages; it does not validate
the current warehouse or the clinical interpretation of flags.
