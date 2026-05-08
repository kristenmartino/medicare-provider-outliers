#!/usr/bin/env python3
"""Stage CMS files in Snowflake and COPY INTO RAW.CMS.* tables.

Reads the same key-pair credentials dbt uses (~/.dbt/profiles.yml — adjust
KEY_PATH / ACCOUNT / USER below if you fork this repo). Idempotent: safe to
re-run; CREATE OR REPLACE the raw tables and stage on each invocation, so a
re-run is a clean reload.

Run after `setup/02_filter_nppes.py` has produced
`data/raw/nppes_individuals_filtered.csv`:

    .venv/bin/python setup/03_load_to_snowflake.py
"""

from __future__ import annotations

from pathlib import Path
import sys
import time

import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

# ---------------------------------------------------------------------------
# Configuration — edit these if you fork this repo
# ---------------------------------------------------------------------------
ACCOUNT = "jrc82992.us-east-1"
USER = "KRISTENMARTINO"
ROLE = "ANALYST"
WAREHOUSE = "DBT_XS_WH"
DATABASE = "RAW"
SCHEMA = "CMS"
KEY_PATH = Path.home() / ".snowflake" / "keys" / "dbt_rsa_key.p8"

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

# (table_name, local_csv_path, ddl). The DDL uses VARCHAR for everything because
# CMS files include sentinel strings ("*", "#") for suppressed values; staging
# models cast types after stripping those.
LOADS = [
    (
        "PART_D_PRESCRIBERS",
        DATA_DIR / "part_d_prescribers_2023.csv",
        """
        CREATE OR REPLACE TABLE RAW.CMS.PART_D_PRESCRIBERS (
            prscrbr_npi          VARCHAR,
            prscrbr_last_org_name VARCHAR,
            prscrbr_first_name   VARCHAR,
            prscrbr_city         VARCHAR,
            prscrbr_state_abrvtn VARCHAR,
            prscrbr_state_fips   VARCHAR,
            prscrbr_type         VARCHAR,
            prscrbr_type_src     VARCHAR,
            brnd_name            VARCHAR,
            gnrc_name            VARCHAR,
            tot_clms             VARCHAR,
            tot_30day_fills      VARCHAR,
            tot_day_suply        VARCHAR,
            tot_drug_cst         VARCHAR,
            tot_benes            VARCHAR,
            ge65_sprsn_flag      VARCHAR,
            ge65_tot_clms        VARCHAR,
            ge65_tot_30day_fills VARCHAR,
            ge65_tot_drug_cst    VARCHAR,
            ge65_tot_day_suply   VARCHAR,
            ge65_bene_sprsn_flag VARCHAR,
            ge65_tot_benes       VARCHAR,
            _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
        )
        """,
    ),
    (
        "PART_B_SERVICES",
        DATA_DIR / "part_b_provider_service_2023.csv",
        # Schema discovered from the live header at load-time — see DDL below
        # after we inspect the file. Placeholder columns expanded by the script.
        None,  # filled in dynamically below
    ),
    (
        "NPPES_NPI",
        DATA_DIR / "nppes_individuals_filtered.csv",
        """
        CREATE OR REPLACE TABLE RAW.CMS.NPPES_NPI (
            npi                    VARCHAR,
            entity_type_code       VARCHAR,
            provider_last_name     VARCHAR,
            provider_first_name    VARCHAR,
            provider_middle_name   VARCHAR,
            provider_credentials   VARCHAR,
            practice_city          VARCHAR,
            practice_state         VARCHAR,
            practice_zip           VARCHAR,
            provider_sex_code      VARCHAR,
            primary_taxonomy_code  VARCHAR,
            enumeration_date       VARCHAR,
            last_update_date       VARCHAR,
            deactivation_date      VARCHAR,
            _loaded_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
        )
        """,
    ),
]


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


def part_b_ddl_from_header(csv_path: Path) -> str:
    """Build the Part B DDL from the live CSV header — its column list is long
    and changes slightly between releases. We mirror it verbatim, lowercased,
    all VARCHAR."""
    with open(csv_path) as f:
        header = f.readline().strip().split(",")
    cols = ",\n            ".join(f"{c.lower():<32} VARCHAR" for c in header)
    return f"""
        CREATE OR REPLACE TABLE RAW.CMS.PART_B_SERVICES (
            {cols},
            _loaded_at                       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
        )
    """


def main() -> int:
    if not KEY_PATH.exists():
        print(f"ERROR: private key not found at {KEY_PATH}", file=sys.stderr)
        return 1

    # Sanity-check all source files before opening a connection
    missing = [p for _, p, _ in LOADS if not p.exists()]
    if missing:
        print("ERROR: missing source files:", file=sys.stderr)
        for m in missing:
            print(f"  {m}", file=sys.stderr)
        return 1

    print(f"Connecting to Snowflake account={ACCOUNT} user={USER} role={ROLE}...")
    conn = snowflake.connector.connect(
        account=ACCOUNT,
        user=USER,
        private_key=load_private_key(),
        role=ROLE,
        warehouse=WAREHOUSE,
        database=DATABASE,
        schema=SCHEMA,
    )
    cur = conn.cursor()

    # Build Part B DDL now that we have the file in hand
    for i, (name, path, ddl) in enumerate(LOADS):
        if name == "PART_B_SERVICES":
            LOADS[i] = (name, path, part_b_ddl_from_header(path))

    try:
        cur.execute(f"USE WAREHOUSE {WAREHOUSE}")
        cur.execute(f"USE ROLE {ROLE}")
        cur.execute(f"USE DATABASE {DATABASE}")
        cur.execute(f"USE SCHEMA {SCHEMA}")

        # CSV file format — CMS files use double-quote escaping
        print("Creating file format CMS_CSV...")
        cur.execute(
            """
            CREATE OR REPLACE FILE FORMAT CMS_CSV
                TYPE = CSV
                FIELD_DELIMITER = ','
                SKIP_HEADER = 1
                FIELD_OPTIONALLY_ENCLOSED_BY = '"'
                NULL_IF = ('', 'NULL', '*')
                EMPTY_FIELD_AS_NULL = TRUE
                TRIM_SPACE = TRUE
                -- Source files don't include the trailing _loaded_at column;
                -- let Snowflake fall back to its DEFAULT for that column.
                ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
            """
        )

        print("Creating internal stage CMS_STAGE...")
        cur.execute("CREATE OR REPLACE STAGE CMS_STAGE FILE_FORMAT = CMS_CSV")

        for name, path, ddl in LOADS:
            print(f"\n=== {name} ===")
            print(f"  Source: {path}  ({path.stat().st_size / 1e9:.2f} GB)")

            print("  Creating table...")
            cur.execute(ddl)

            print("  PUT to stage (with auto-compression to gzip)...")
            t0 = time.time()
            cur.execute(
                f"PUT 'file://{path}' @CMS_STAGE/{name.lower()}/ "
                "AUTO_COMPRESS=TRUE OVERWRITE=TRUE PARALLEL=8"
            )
            print(f"  PUT done in {time.time() - t0:.0f}s")

            print("  COPY INTO from stage...")
            t0 = time.time()
            cur.execute(
                f"COPY INTO RAW.CMS.{name} "
                f"FROM @CMS_STAGE/{name.lower()}/ "
                "FILE_FORMAT = (FORMAT_NAME = CMS_CSV) "
                "ON_ERROR = 'ABORT_STATEMENT'"
            )
            (rows,) = cur.execute(f"SELECT count(*) FROM RAW.CMS.{name}").fetchone()
            print(f"  COPY done in {time.time() - t0:.0f}s — {rows:,} rows loaded")

        print("\nAll loads complete.")
    finally:
        cur.close()
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
