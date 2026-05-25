# Setup

One-time bootstrap to create the Snowflake objects, download the CMS source files, pre-filter NPPES, and load everything into `RAW.CMS.*`. After these four steps, `dbt build` is the only command you ever need to run.

## Prereqs

- Snowflake free trial (see top-level [README](../README.md#reproduce))
- Python 3.11+ venv with `dbt-snowflake` and `duckdb` installed (`pip install -r ../requirements.txt`)
- ~20 GB free disk for the raw files

## Run order

### 1. Snowflake objects — [`01_snowflake_setup.sql`](./01_snowflake_setup.sql)

In a Snowsight worksheet as `ACCOUNTADMIN`:

1. Paste the entire script
2. **Select all** (⌘ + A) so every statement runs, then click ▶ **Run** (or ⌘ + Return)
3. Final `SELECT` should return role=`ANALYST`, warehouse=`DBT_XS_WH`, user=`<YOUR_USER>`

### 2. Download CMS files

The URLs below are pinned to the vintage the current marts were built on (Part D / Part B 2023, NPPES April 2026). CMS embeds per-release UUIDs in their CDN paths — those UUIDs change every release and the URLs below will 404 once enough time passes.

**To get current URLs** (e.g., the 2024 vintage CMS published in May 2026):

```bash
.venv/bin/python setup/02a_resolve_cms_urls.py
```

The resolver hits `https://data.cms.gov/data.json`, looks up Part D / Part B by dataset title (the stable identifier), HEAD-probes recent NPPES monthly snapshots, and writes [`setup/data_manifest.json`](./data_manifest.json) with the current URLs + sizes. Inspect that file to see what's available, then update the curl URLs below or just paste them into a fresh terminal.

```bash
mkdir -p ../data/raw && cd ../data/raw

# Part D Prescribers (2023, ~3.6 GB)
curl -sLo part_d_prescribers_2023.csv \
  'https://data.cms.gov/sites/default/files/2025-04/0d5915ce-002c-4d87-bde8-24ffb08bb6cc/MUP_DPR_RY25_P04_V10_DY23_NPIBN.csv'

# Part B Physician & Other Practitioners (2023, ~1.5 GB)
curl -sLo part_b_provider_service_2023.csv \
  'https://data.cms.gov/sites/default/files/2025-04/e3f823f8-db5b-4cc7-ba04-e7ae92b99757/MUP_PHY_R25_P05_V20_D23_Prov_Svc.csv'

# NPPES April 2026 (~1 GB zip; 11.6 GB extracted)
curl -sLo nppes_apr2026.zip \
  'https://download.cms.gov/nppes/NPPES_Data_Dissemination_April_2026_V2.zip'

# Extract just the main npidata file
unzip -o nppes_apr2026.zip 'npidata_pfile_*'

cd ../..
```

### 3. Pre-filter NPPES — [`02_filter_nppes.py`](./02_filter_nppes.py)

```bash
.venv/bin/python setup/02_filter_nppes.py
```

Drops 300+ columns to ~14, filters to Entity Type Code = 1 (individuals). Output: `data/raw/nppes_individuals_filtered.csv` (~1.5 GB instead of 11.4).

### 4. Load to Snowflake — [`03_load_to_snowflake.py`](./03_load_to_snowflake.py)

```bash
.venv/bin/python setup/03_load_to_snowflake.py
```

Creates `RAW.CMS.{PART_D_PRESCRIBERS, PART_B_SERVICES, NPPES_NPI}`, an internal stage, and a CSV file format. PUTs files (auto-compressed gzip), then COPY INTO. Idempotent — uses `CREATE OR REPLACE`.

### 5. Validate — [`04_validate_counts.sql`](./04_validate_counts.sql)

In Snowsight, run as `ANALYST`. Confirms row counts and null rates on join keys.

## What gets created

| Object | Purpose |
|---|---|
| `WAREHOUSE DBT_XS_WH` | XS, 60s auto-suspend; used for all dbt builds |
| `DATABASE RAW` | Landing zone for CMS source files |
| `SCHEMA RAW.CMS` | All CMS tables (Part D, Part B, NPPES) |
| `DATABASE ANALYTICS` | dbt-built models (schemas created automatically) |
| `ROLE ANALYST` | Working role for dbt and Hex |
| `STAGE RAW.CMS.CMS_STAGE` | Internal stage for the source CSVs |
| `FILE FORMAT RAW.CMS.CMS_CSV` | Reusable CSV format with CMS suppression sentinels treated as null |
