-- ============================================================================
-- Snowflake setup for CMS Medicare → dbt → Hex sprint
-- Run this entire script in a Snowsight worksheet as ACCOUNTADMIN.
-- It is idempotent (CREATE ... IF NOT EXISTS), so re-running is safe.
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ----------------------------------------------------------------------------
-- 1. Dedicated XS warehouse for dbt builds
--    AUTO_SUSPEND = 60s and INITIALLY_SUSPENDED to conserve trial credits.
-- ----------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS DBT_XS_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'XS warehouse for dbt builds — conserves trial credits';

-- ----------------------------------------------------------------------------
-- 2. Databases & schemas
--    RAW       — landing zone for CMS source files
--    ANALYTICS — dbt-built models (staging, intermediate, marts schemas)
-- ----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS RAW
  COMMENT = 'Raw CMS Medicare landings — Part D, Part B, NPPES';

CREATE SCHEMA IF NOT EXISTS RAW.CMS
  COMMENT = 'CMS source tables, populated by COPY INTO';

CREATE DATABASE IF NOT EXISTS ANALYTICS
  COMMENT = 'dbt-built analytics layers — staging, intermediate, marts';

-- ----------------------------------------------------------------------------
-- 3. ANALYST role — used by dbt for builds and by Hex for reads
-- ----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ANALYST
  COMMENT = 'dbt + Hex working role';

-- Warehouse access
GRANT USAGE ON WAREHOUSE DBT_XS_WH TO ROLE ANALYST;

-- Read access to RAW for dbt staging, plus the writes needed to manage the
-- one-time CMS source loads (stage, file format, tables). ANALYST owns the
-- end-to-end pipeline; ACCOUNTADMIN is only used during initial setup.
GRANT USAGE ON DATABASE RAW TO ROLE ANALYST;
GRANT USAGE ON SCHEMA RAW.CMS TO ROLE ANALYST;
GRANT CREATE TABLE       ON SCHEMA RAW.CMS TO ROLE ANALYST;
GRANT CREATE STAGE       ON SCHEMA RAW.CMS TO ROLE ANALYST;
GRANT CREATE FILE FORMAT ON SCHEMA RAW.CMS TO ROLE ANALYST;
GRANT SELECT ON ALL TABLES    IN SCHEMA RAW.CMS TO ROLE ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.CMS TO ROLE ANALYST;

-- Full access to ANALYTICS (dbt creates schemas + tables here)
GRANT USAGE ON DATABASE ANALYTICS TO ROLE ANALYST;
GRANT CREATE SCHEMA ON DATABASE ANALYTICS TO ROLE ANALYST;

-- ----------------------------------------------------------------------------
-- 4. Grant the ANALYST role to your user.
--    Replace KRISTENMARTINO with the value of `SELECT CURRENT_USER();`
--    if you're forking this repo.
-- ----------------------------------------------------------------------------
GRANT ROLE ANALYST TO USER KRISTENMARTINO;

-- ----------------------------------------------------------------------------
-- 5. Verify by switching into ANALYST and listing what we can see
-- ----------------------------------------------------------------------------
USE ROLE ANALYST;
USE WAREHOUSE DBT_XS_WH;

SHOW DATABASES;          -- should include RAW, ANALYTICS
SHOW SCHEMAS IN RAW;     -- should include CMS
SELECT CURRENT_ROLE() AS role,
       CURRENT_WAREHOUSE() AS warehouse,
       CURRENT_USER() AS user;
