# Snowflake setup

One-time DDL to create the warehouse, databases, role, and grants used by the dbt project.

## Run

1. Open Snowsight at [app.snowflake.com](https://app.snowflake.com/).
2. Make sure your role at top-right is **ACCOUNTADMIN**.
3. **Projects** → **Worksheets** → **+ Worksheet** (top-right).
4. Paste the entire contents of [`01_snowflake_setup.sql`](./01_snowflake_setup.sql) into the worksheet.
5. **Select all** (⌘ + A) so every statement runs, then click ▶ **Run** (or ⌘ + Return). The default Run button only executes the statement under the cursor — selecting all is what triggers a multi-statement batch.

You should see:
- One row per `CREATE` / `GRANT` statement returned.
- The final `SHOW DATABASES` lists `RAW` and `ANALYTICS`.
- The final `SELECT CURRENT_ROLE()` returns `ANALYST` + `DBT_XS_WH`.

## What gets created

| Object | Purpose |
|---|---|
| `WAREHOUSE DBT_XS_WH` | XS, 60s auto-suspend; used for all dbt builds |
| `DATABASE RAW` | Landing zone for CMS source files |
| `SCHEMA RAW.CMS` | All CMS tables (Part D, Part B, NPPES) |
| `DATABASE ANALYTICS` | dbt-built models (schemas created automatically) |
| `ROLE ANALYST` | Working role for dbt and Hex |
