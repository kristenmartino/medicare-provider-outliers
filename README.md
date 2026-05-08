# CMS Medicare → Snowflake → dbt → Hex

> Provider cost & volume outlier detection across CMS Part D, Part B, and NPPES — modeled in dbt on Snowflake, surfaced via an interactive Hex notebook.

**Status:** Sprint in progress (started 2026-05-08).

## Stack

| Layer | Tool |
|---|---|
| Source files | CMS Provider Data Catalog + NPPES Registry |
| Warehouse | Snowflake (Standard, free trial) |
| Transformation | dbt Core 1.9 |
| BI / notebook | Hex (free tier) |
| Docs | dbt docs published to GitHub Pages |
| CI | GitHub Actions |

## Architecture

```
CMS source CSVs  ─►  Snowflake stage  ─►  RAW.CMS.*  ─►  dbt  ─►  ANALYTICS.{STAGING,INTERMEDIATE,MARTS}  ─►  Hex
```

## Repo layout

```
.
├── setup/                  # One-time Snowflake DDL (run in Snowsight)
├── models/
│   ├── staging/            # 1-1 with sources, cleaned + cast
│   ├── intermediate/       # Provider-level aggregates, peer-group stats
│   └── marts/              # dim_provider, fact tables, mart_provider_outliers
├── seeds/                  # Reference data (taxonomy → specialty map)
├── tests/                  # Singular tests
├── macros/                 # Reusable Jinja
├── docs/                   # Architecture diagrams, methodology notes
└── .github/workflows/      # CI: dbt build + dbt docs publish
```

## Reproduce

1. **Snowflake** — sign up for a free trial at [signup.snowflake.com](https://signup.snowflake.com/), then in Snowsight run `setup/01_snowflake_setup.sql` as ACCOUNTADMIN.
2. **dbt** — Python 3.11+ required. `python3.13 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`
3. **Profile** — copy `profiles.yml.example` to `~/.dbt/profiles.yml` and fill in account locator, user, password.
4. **Verify** — `dbt debug` should pass all checks.
5. **Ingest** — see `setup/02_load_cms_data.md` for the CMS download + `COPY INTO` flow.
6. **Build** — `dbt deps && dbt seed && dbt build`
7. **Docs** — `dbt docs generate && dbt docs serve`

## Methodology — provider outliers

Providers are flagged as outliers when their cost or volume metric exceeds **2.0 modified-z-score** (MAD-based) within their **(specialty × state)** peer group. Peer groups with fewer than 30 providers are excluded to avoid small-cell false positives. Methodology details live in `docs/methodology.md` and the Hex notebook's Methodology tab.
