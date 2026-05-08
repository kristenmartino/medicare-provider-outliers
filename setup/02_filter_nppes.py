#!/usr/bin/env python3
"""Pre-filter the NPPES NPI dissemination file to the columns we actually use.

NPPES ships a ~11 GB CSV with 300+ columns and ~7M rows. We only need ~14 columns,
and we filter to Entity Type Code = 1 (individual providers — the project ignores
organizational NPIs). This cuts the file roughly 8x and dramatically reduces both
upload time to Snowflake and credit usage during loads.

Run after extracting `npidata_pfile_*.csv` from the NPPES zip:

    cd data/raw && unzip -o nppes_apr2026.zip 'npidata_pfile_*' && cd ../..
    .venv/bin/python setup/02_filter_nppes.py

Output: data/raw/nppes_individuals_filtered.csv
"""

from pathlib import Path
import glob
import sys
import time

import duckdb

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
SOURCE_GLOB = str(DATA_DIR / "npidata_pfile_*.csv")
# Exclude the small fileheader file that ships alongside
SOURCE_FILES = [f for f in glob.glob(SOURCE_GLOB) if "fileheader" not in f]
OUTPUT_PATH = DATA_DIR / "nppes_individuals_filtered.csv"


def main() -> int:
    if not SOURCE_FILES:
        print(f"ERROR: no npidata_pfile_*.csv found in {DATA_DIR}", file=sys.stderr)
        print("Did you `unzip` the NPPES bundle yet?", file=sys.stderr)
        return 1

    src = SOURCE_FILES[0]
    print(f"Source : {src}")
    print(f"Output : {OUTPUT_PATH}")
    print()

    start = time.time()
    con = duckdb.connect()

    # DuckDB streams the CSV — peak memory stays modest even for 11 GB input.
    con.execute(
        f"""
        COPY (
            SELECT
                "NPI"                                                                    AS npi,
                "Entity Type Code"                                                       AS entity_type_code,
                "Provider Last Name (Legal Name)"                                        AS provider_last_name,
                "Provider First Name"                                                    AS provider_first_name,
                "Provider Middle Name"                                                   AS provider_middle_name,
                "Provider Credential Text"                                               AS provider_credentials,
                "Provider Business Practice Location Address City Name"                  AS practice_city,
                "Provider Business Practice Location Address State Name"                 AS practice_state,
                "Provider Business Practice Location Address Postal Code"                AS practice_zip,
                "Provider Sex Code"                                                      AS provider_sex_code,
                "Healthcare Provider Taxonomy Code_1"                                    AS primary_taxonomy_code,
                "Provider Enumeration Date"                                              AS enumeration_date,
                "Last Update Date"                                                       AS last_update_date,
                "NPI Deactivation Date"                                                  AS deactivation_date
            FROM read_csv('{src}', header=true, all_varchar=true, ignore_errors=false)
            WHERE "Entity Type Code" = '1'
              AND ("NPI Deactivation Date" IS NULL OR "NPI Deactivation Date" = '')
        ) TO '{OUTPUT_PATH}' (HEADER, DELIMITER ',', QUOTE '"', ESCAPE '"')
        """
    )

    rows = con.execute(f"SELECT count(*) FROM read_csv_auto('{OUTPUT_PATH}')").fetchone()[0]
    out_size_mb = OUTPUT_PATH.stat().st_size / (1024 * 1024)
    src_size_mb = Path(src).stat().st_size / (1024 * 1024)

    print()
    print(f"Wrote {rows:,} active individual-provider rows")
    print(f"Output size: {out_size_mb:,.0f} MB  (down from {src_size_mb:,.0f} MB)")
    print(f"Elapsed: {time.time() - start:,.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
