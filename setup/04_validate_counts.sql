-- ============================================================================
-- Post-load validation: row counts in Snowflake should match the source files.
-- Run after `setup/03_load_to_snowflake.py` completes.
-- ============================================================================

USE ROLE ANALYST;
USE WAREHOUSE DBT_XS_WH;
USE DATABASE RAW;
USE SCHEMA CMS;

-- 1. Row counts per source table
SELECT 'PART_D_PRESCRIBERS' AS source_table, COUNT(*) AS row_count FROM PART_D_PRESCRIBERS
UNION ALL
SELECT 'PART_B_SERVICES',     COUNT(*) FROM PART_B_SERVICES
UNION ALL
SELECT 'NPPES_NPI',           COUNT(*) FROM NPPES_NPI
ORDER BY source_table;

-- 2. Distinct NPI counts — useful sanity checks against published CMS totals
SELECT 'distinct_part_d_prescribers' AS metric, COUNT(DISTINCT prscrbr_npi) AS value FROM PART_D_PRESCRIBERS
UNION ALL
SELECT 'distinct_part_b_providers',         COUNT(DISTINCT rndrng_npi)        FROM PART_B_SERVICES
UNION ALL
SELECT 'distinct_nppes_individuals',        COUNT(DISTINCT npi)                FROM NPPES_NPI;

-- 3. Spot-check loaded_at — every row should have today's load timestamp
SELECT 'PART_D' AS source, MIN(_loaded_at) AS earliest, MAX(_loaded_at) AS latest FROM PART_D_PRESCRIBERS
UNION ALL
SELECT 'PART_B', MIN(_loaded_at), MAX(_loaded_at) FROM PART_B_SERVICES
UNION ALL
SELECT 'NPPES',  MIN(_loaded_at), MAX(_loaded_at) FROM NPPES_NPI;

-- 4. Quick null check on join keys — should all be ~zero
SELECT
    SUM(CASE WHEN prscrbr_npi IS NULL THEN 1 ELSE 0 END) AS null_npi_part_d
FROM PART_D_PRESCRIBERS;

SELECT
    SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) AS null_npi_nppes
FROM NPPES_NPI;
