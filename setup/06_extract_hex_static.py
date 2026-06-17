#!/usr/bin/env python3
"""Extract small, static per-tab result sets for the Hex notebook.

Why this exists
---------------
The published Hex app caches its last-run cells, but any *viewer interaction*
(MAD-threshold slider, metric / specialty / state filters, NPI drill-down)
re-queries Snowflake. Once the free-trial warehouse lapses (~2026-06-06) those
re-queries fail and the app's interactivity dies.

This script pre-materializes the *small* result sets behind each tab into static
CSVs under ``docs/hex_data/``. The Hex cells are then rewired to read those CSVs
(DuckDB-over-dataframe SQL, same column names) so the slider/metric/state/NPI
controls keep working client-side with no live warehouse. See
``docs/hex_notebook_spec.md`` → "Static / offline mode" for the rewired cells and
the fidelity notes.

Run while the trial is still live, using the same key-pair creds dbt uses:

    .venv/bin/python setup/06_extract_hex_static.py

Idempotent: overwrites the CSVs on each run. Tiny warehouse cost (a handful of
aggregations + two top-1000 window scans over the 7M-row mart).
"""

from __future__ import annotations

import csv
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

# ---------------------------------------------------------------------------
# Configuration — mirrors setup/03_load_to_snowflake.py (edit if you fork)
# ---------------------------------------------------------------------------
ACCOUNT = "jrc82992.us-east-1"
USER = "KRISTENMARTINO"
ROLE = "ANALYST"
WAREHOUSE = "DBT_XS_WH"
DATABASE = "ANALYTICS"
KEY_PATH = Path.home() / ".snowflake" / "keys" / "dbt_rsa_key.p8"

MART = "analytics.marts.mart_provider_outliers"
DIM = "analytics.marts.dim_provider"

OUT_DIR = Path(__file__).resolve().parent.parent / "docs" / "hex_data"

# Tab-2 cut: top-N rows per metric by |modified z|. The 1000th-ranked |mz| is
# 34-739 across the six metrics (>> the slider's 10.0 ceiling), so this frame is
# a pixel-identical reproduction of the live Tab-2 query across the whole slider
# range for the no-filter case. Raise this only if you want richer specialty/
# state filter slices (it back-fills lower-ranked providers a narrow filter would
# surface live). 1000 keeps the CSV ~0.5 MB and trivial to upload on Hex free.
TOP_N = 1000

# Tab-3 drill-down: how many documented top outliers to pre-bake as demo NPIs.
DEMO_K = 6

# The six selectable metrics, with the modified-z and per-metric peer-coverage
# column each one gates on (matches mart_provider_outliers.sql lines 121-133 and
# the Tab-2 CASE expressions in the spec).
METRICS = [
    # (metric_name,            value_col,                mz_col,                 peer_n_col)
    ("total_drug_cost",        "total_drug_cost",        "mz_drug_cost",         "peer_n_part_d"),
    ("part_d_total_claims",    "part_d_total_claims",    "mz_part_d_claims",     "peer_n_part_d"),
    ("brand_cost_share",       "brand_cost_share",       "mz_brand_cost_share",  "peer_n_brand_share"),
    ("avg_cost_per_claim",     "avg_cost_per_claim",     "mz_avg_cost_per_claim","peer_n_avg_cost_per_claim"),
    ("total_medicare_payment", "total_medicare_payment", "mz_part_b_payment",    "peer_n_part_b"),
    ("part_b_total_services",  "part_b_total_services",  "mz_part_b_services",   "peer_n_part_b"),
]

# Per-metric peer-coverage floor the mart applies to every flag. The Tab-2
# min_peer_n slider's minimum is also 30, so 30 is the static frame's natural
# floor — rows below it can never appear in the live app either.
PEER_FLOOR = 30


def load_private_key():
    with open(KEY_PATH, "rb") as f:
        pkey = serialization.load_pem_private_key(
            f.read(), password=None, backend=default_backend()
        )
    return pkey.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def fmt(v):
    """CSV-friendly value formatting.

    - bools -> lowercase true/false so DuckDB's read_csv types them as BOOLEAN
    - None  -> '' (read back as NULL)
    - Decimal/int/float/str -> str() (csv.writer handles quoting)
    """
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return ""
    if isinstance(v, Decimal):
        return format(v, "f")  # avoid scientific notation
    return v


def dump(cur, name: str, sql: str) -> tuple[int, list[str]]:
    """Run ``sql``, write ``OUT_DIR/<name>.csv`` with lowercased headers."""
    cur.execute(sql)
    cols = [d[0].lower() for d in cur.description]
    rows = cur.fetchall()
    path = OUT_DIR / f"{name}.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in rows:
            w.writerow([fmt(v) for v in r])
    print(f"  wrote {path.relative_to(OUT_DIR.parent.parent)}  "
          f"({len(rows):,} rows x {len(cols)} cols)")
    return len(rows), cols


# ---------------------------------------------------------------------------
# SQL builders
# ---------------------------------------------------------------------------

def tab1_sql() -> str:
    # Spec Tab-1 "Overview KPIs", verbatim.
    return f"""
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
    from {MART}
    """


def tab2_sql() -> str:
    # Melt the six metrics into one tidy frame, top-N per metric by |mz|, with
    # the per-metric peer floor + value-not-null gate already applied. Hex then
    # filters `where metric = '{{metric}}'` and re-applies threshold/peer_n/
    # specialty/state client-side.
    parts = []
    for metric, val, mz, pn in METRICS:
        parts.append(f"""
        select
            '{metric}'                  as metric,
            npi,
            provider_full_name,
            specialty,
            state,
            city,
            peer_group_n,
            {pn}                        as peer_n_metric,
            {val}                       as metric_value,
            {mz}                        as modified_z_score
        from {MART}
        where {val} is not null
          and {pn} >= {PEER_FLOOR}
          and abs({mz}) >= 1.0
        qualify row_number() over (order by abs({mz}) desc nulls last, npi) <= {TOP_N}
        """)
    return "\nunion all\n".join(parts)


def tab4_sql() -> str:
    # Spec Tab-4 "State aggregates", verbatim. geo_metric is a client-side
    # column pick over these already-computed columns.
    return f"""
    select
        state,
        count(*)                                                      as n_providers,
        count_if(is_outlier_any_mad)                                  as flagged_mad,
        count_if(is_outlier_any_zscore)                               as flagged_zscore,
        round(100.0 * count_if(is_outlier_any_mad) / count(*), 2)     as pct_flagged_mad,
        round(100.0 * count_if(is_outlier_any_zscore) / count(*), 2)  as pct_flagged_zscore,
        round(sum(total_drug_cost), 0)                                as total_part_d_spend,
        round(sum(total_medicare_payment), 0)                         as total_part_b_spend
    from {MART}
    where state is not null
    group by state
    order by state
    """


# Reusable demo-NPI selector: top-K documented drug-cost MAD outliers, stable
# tiebreak on npi so the set is reproducible run-to-run.
_DEMO_CTE = f"""
    demo as (
        select *
        from {MART}
        where outlier_mad_drug_cost and total_drug_cost is not null
        qualify row_number() over (order by mz_drug_cost desc nulls last, npi) <= {DEMO_K}
    )
"""


def tab3_providers_sql() -> str:
    # Curated drill-down summary for the demo NPIs: the columns the Tab-3 widgets
    # show, plus the nucc_* taxonomy fields the spec joins from dim_provider.
    return f"""
    with {_DEMO_CTE}
    select
        d.npi,
        d.provider_full_name,
        d.specialty,
        d.taxonomy_code,
        d.state,
        d.city,
        d.peer_group_n,
        d.total_drug_cost,
        d.mz_drug_cost,
        d.is_outlier_any_mad,
        d.part_d_total_claims,
        d.mz_part_d_claims,
        d.brand_cost_share,
        d.mz_brand_cost_share,
        d.avg_cost_per_claim,
        d.mz_avg_cost_per_claim,
        d.total_medicare_payment,
        d.mz_part_b_payment,
        d.part_b_total_services,
        d.mz_part_b_services,
        p.nucc_grouping,
        p.nucc_classification,
        p.nucc_specialization
    from demo d
    left join {DIM} p using (npi)
    order by d.mz_drug_cost desc
    """


def tab3_peer_dist_sql() -> str:
    # Long frame: for each demo NPI, its own total_drug_cost ('this_provider')
    # plus every peer's total_drug_cost in the same specialty+state ('peer_group')
    # — exactly the histogram series the spec's Tab-3 peer-distribution cell
    # builds, keyed by demo_npi so Hex can filter to the selected provider.
    return f"""
    with {_DEMO_CTE}
    select
        d.npi              as demo_npi,
        'this_provider'    as series,
        d.total_drug_cost  as value
    from demo d
    union all
    select
        d.npi              as demo_npi,
        'peer_group'       as series,
        m.total_drug_cost  as value
    from demo d
    join {MART} m
      on m.specialty = d.specialty
     and m.state     = d.state
    where m.total_drug_cost is not null
    order by demo_npi, series, value desc
    """


def write_manifest(cur, counts: dict[str, int]) -> None:
    """Small README beside the CSVs: provenance, row counts, refresh command."""
    today = date.today().isoformat()
    lines = [
        "# Hex static datasets",
        "",
        f"Generated by `setup/06_extract_hex_static.py` on **{today}** from "
        f"`{MART}` ({cur.execute(f'select count(*) from {MART}').fetchone()[0]:,} rows).",
        "",
        "These small CSVs back the published Hex app's interactive cells so the "
        "MAD-threshold slider, metric / specialty / state filters, and the "
        "drill-down keep working **after the Snowflake trial warehouse lapses**. "
        "See `docs/hex_notebook_spec.md` → \"Static / offline mode\" for the "
        "rewired Hex cells and the fidelity notes.",
        "",
        "| File | Rows | Backs |",
        "|---|---:|---|",
        f"| `tab1_overview_kpis.csv` | {counts['tab1_overview_kpis']:,} | Tab 1 KPI tiles |",
        f"| `tab2_outliers_top{TOP_N}.csv` | {counts[f'tab2_outliers_top{TOP_N}']:,} | "
        f"Tab 2 outlier table (top-{TOP_N} per metric, peer floor {PEER_FLOOR} applied) |",
        f"| `tab3_demo_providers.csv` | {counts['tab3_demo_providers']:,} | "
        "Tab 3 drill-down summary (curated demo NPIs) |",
        f"| `tab3_demo_peer_dist.csv` | {counts['tab3_demo_peer_dist']:,} | "
        "Tab 3 peer-distribution histogram (curated demo NPIs) |",
        f"| `tab4_state_aggregates.csv` | {counts['tab4_state_aggregates']:,} | Tab 4 state map |",
        "",
        "Refresh (while the warehouse is live):",
        "",
        "```bash",
        ".venv/bin/python setup/06_extract_hex_static.py",
        "```",
        "",
    ]
    path = OUT_DIR / "README.md"
    path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  wrote {path.relative_to(OUT_DIR.parent.parent)}")


def main() -> int:
    if not KEY_PATH.exists():
        print(f"ERROR: private key not found at {KEY_PATH}", file=sys.stderr)
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Connecting account={ACCOUNT} user={USER} role={ROLE} wh={WAREHOUSE}...")
    conn = snowflake.connector.connect(
        account=ACCOUNT, user=USER, private_key=load_private_key(),
        role=ROLE, warehouse=WAREHOUSE, database=DATABASE,
    )
    cur = conn.cursor()
    counts: dict[str, int] = {}
    try:
        print("\nExtracting static datasets -> docs/hex_data/")
        n, _ = dump(cur, "tab1_overview_kpis", tab1_sql());        counts["tab1_overview_kpis"] = n
        n, _ = dump(cur, f"tab2_outliers_top{TOP_N}", tab2_sql()); counts[f"tab2_outliers_top{TOP_N}"] = n
        n, _ = dump(cur, "tab3_demo_providers", tab3_providers_sql()); counts["tab3_demo_providers"] = n
        n, _ = dump(cur, "tab3_demo_peer_dist", tab3_peer_dist_sql()); counts["tab3_demo_peer_dist"] = n
        n, _ = dump(cur, "tab4_state_aggregates", tab4_sql());     counts["tab4_state_aggregates"] = n
        write_manifest(cur, counts)
        print("\nAll extracts complete.")
    finally:
        cur.close()
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
