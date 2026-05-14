-- ============================================================================
-- Trial credit-usage monitoring.
--
-- Run as ACCOUNTADMIN in a Snowsight worksheet. The ACCOUNT_USAGE views
-- aren't granted to ANALYST by default and have a documented ~45-minute lag,
-- so query results may slightly trail real-time usage.
--
-- Trial accounts get $400 in credits over 30 days. The credit *count* varies
-- by edition and cloud:
--   Standard / AWS us-east-1  ≈ 138 credits ($2.90/credit on-demand)
--   Enterprise / AWS us-east-1 ≈ 100 credits ($4.00/credit on-demand)
-- Adjust CREDIT_BUDGET below to match what your trial actually granted.
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SNOWFLAKE;
USE SCHEMA ACCOUNT_USAGE;

-- ----------------------------------------------------------------------------
-- Set your trial budget once. Defaults to 138 (Standard / AWS).
-- ----------------------------------------------------------------------------
SET CREDIT_BUDGET = 138.0;


-- 1. Daily credit burn by warehouse (last 30 days)
-- ----------------------------------------------------------------------------
-- Tells you which warehouse is spending what and when. For this project
-- DBT_XS_WH should be ~100% of the cost; if anything else appears, the
-- auto-suspend isn't working or someone resumed a warehouse manually.
SELECT
    DATE_TRUNC('day', start_time)            AS usage_date,
    warehouse_name,
    ROUND(SUM(credits_used), 3)              AS credits,
    ROUND(SUM(credits_used_cloud_services), 3) AS credits_cloud_services
FROM warehouse_metering_history
WHERE start_time >= CURRENT_DATE - 30
GROUP BY 1, 2
ORDER BY 1 DESC, credits DESC;


-- 2. Top 20 most expensive queries in the last 7 days
-- ----------------------------------------------------------------------------
-- ACCOUNT_USAGE.QUERY_HISTORY doesn't store credit-cost directly. Use
-- elapsed-time × warehouse-size as a defensible proxy: longer queries on
-- larger warehouses cost more. Sort by total_elapsed_time and look at the
-- query_text to find avoidable scans, missed predicate pushdown, etc.
SELECT
    query_id,
    user_name,
    warehouse_name,
    warehouse_size,
    query_type,
    ROUND(total_elapsed_time / 1000.0, 1)     AS elapsed_sec,
    ROUND(bytes_scanned / POWER(2, 30), 2)    AS gb_scanned,
    rows_produced,
    start_time,
    LEFT(query_text, 120)                     AS query_preview
FROM query_history
WHERE start_time >= CURRENT_DATE - 7
  AND warehouse_name = 'DBT_XS_WH'
  AND query_type IN ('SELECT', 'CREATE_TABLE_AS_SELECT', 'COPY', 'INSERT', 'MERGE')
ORDER BY total_elapsed_time DESC
LIMIT 20;


-- 3. Trial credit runway — extrapolate from the last 7 days
-- ----------------------------------------------------------------------------
-- Burn-rate forecast against the configured CREDIT_BUDGET. Returns days
-- remaining at recent burn rate, with caveats:
--   - assumes you keep doing what you've been doing (a fresh dbt build cycle
--     burns ~0.05 credits on XS, far below the trial budget)
--   - excludes Snowflake's free-tier cloud-services credit allowance
--   - dev-iteration days will skew higher; "lazy" weeks lower
WITH usage AS (
    SELECT SUM(credits_used) AS credits_used_total
    FROM warehouse_metering_history
),
recent AS (
    SELECT SUM(credits_used) AS credits_last_7
    FROM warehouse_metering_history
    WHERE start_time >= CURRENT_DATE - 7
)
SELECT
    ROUND(credits_used_total, 2)                                AS credits_used_total,
    $CREDIT_BUDGET                                              AS credit_budget,
    ROUND($CREDIT_BUDGET - credits_used_total, 2)               AS credits_remaining,
    ROUND(100.0 * credits_used_total / $CREDIT_BUDGET, 1)       AS pct_consumed,
    ROUND(credits_last_7 / 7.0, 3)                              AS avg_daily_burn_last_7d,
    CASE
        WHEN credits_last_7 > 0 THEN
            ROUND(($CREDIT_BUDGET - credits_used_total) / (credits_last_7 / 7.0), 1)
    END                                                         AS days_remaining_at_recent_burn
FROM usage, recent;


-- 4. (Optional) Warehouses still consuming credits right now
-- ----------------------------------------------------------------------------
-- A warehouse with high recent activity and no auto-suspend would be a
-- silent credit drain. This snapshots active sessions.
SELECT
    name,
    size,
    auto_suspend,
    auto_resume,
    state
FROM SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSES
ORDER BY name;
