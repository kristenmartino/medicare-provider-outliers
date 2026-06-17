# Decision record — why the project is built the way it is

> Architecture-decision-record (ADR) style notes for `mart_provider_outliers` and the
> pipeline around it. Companion to [`methodology.md`](./methodology.md) (the *statistical*
> audit trail) — this file is the *engineering* audit trail: every non-obvious choice, the
> reason for it, and an honest verdict on how it sits against analytics-engineering best
> practice.

**Verdict legend**

- ✅ **Standard** — the conventional best-practice choice.
- ⚙️ **Tradeoff** — a deliberate, defensible decision given scope; a different context would choose differently.
- 🔧 **Gap** — a real limitation of the current build, with the next step named.

**Framing principle.** A scope tradeoff (⚙️) is stated as a decision: *"I did X because Y; the next iteration is Z."* A gap (🔧) is named and owned with its fix. Nothing here claims a thing runs or passes that doesn't — the value of the doc is that every line survives a follow-up question.

---

## A. Stack & infrastructure

**ELT, not ETL.** Load raw files faithfully, transform in-warehouse with dbt. Keeps every transformation versioned, tested, and lineage-tracked in one place, and pushes compute to Snowflake. ✅ The modern-data-stack default.

**Snowflake — free trial, XS warehouse, 60s auto-suspend, initially suspended.** Separation of storage/compute scales to 43.7M source rows trivially; the XS sizing and aggressive auto-suspend are explicit credit-budget discipline on a $400 / 30-day trial. ⚙️ Treated trial credits like a real FinOps budget.

**dbt Core, not dbt Cloud.** Free, git-native, CI-portable, no lock-in. ✅ The only thing Cloud would add here is a managed scheduler (see §G).

**RSA key-pair auth.** Snowflake enforces MFA on password auth by default since late 2024; key-pair is the MFA-exempt path for programmatic/CI access. Secrets stay out of git via `profiles.yml.example` + `.gitignore`. ✅ Security best practice.

**Evidence (BI-as-code) for the live app, served from committed CSV extracts.** SQL + Markdown → static site (DuckDB-WASM), so the dashboard keeps working after the trial warehouse lapses — no live-warehouse dependency, fully reproducible from the repo. ✅ Strong portfolio choice. *(The high-fidelity Hex five-tab set is a mockup + spec, not a built notebook — see `mockups/hex_dashboard/`.)*

**dbt docs on GitHub Pages.** Free hosting of the lineage graph, column-level docs, and test coverage — the self-documenting-pipeline practice. ✅

## B. Ingestion & loading

**Hand-rolled Python loader (`snowflake-connector-python`), not Fivetran/Airbyte.** The sources are static annual bulk files, not a streaming/operational API; a managed connector would add cost and config for no benefit. ⚙️ Tool matched to cadence — bulk public files are a scripted `COPY INTO`, not CDC.

**DuckDB pre-filter of NPPES (11.4 GB → ~1.5 GB).** NPPES ships 300+ columns × ~7M rows; we use ~14 and only individuals. Filtering locally before upload cuts load time and Snowflake credits ~8×. ✅ Push cheap filtering as far upstream as possible.

**Land raw as all-`VARCHAR`, cast in staging.** CMS embeds suppression sentinels (`*`) in numeric columns; VARCHAR landing avoids `COPY` failures, and staging does typed `try_cast` after the file format nulls the sentinels. ✅ Raw layer stays faithful to source; typing happens in transform.

**`COPY INTO` via internal stage + `PUT` (auto-gzip); file format `NULL_IF = ('', 'NULL', '*')`.** Canonical Snowflake bulk-load path; the `NULL_IF` is surgical handling of CMS's <11-beneficiary suppression convention. ✅

**`CREATE OR REPLACE` full reload, not row-level incremental.** Annual full files — a re-run is a clean reload with no merge logic to get wrong. ⚙️ Correct for annual snapshots; multi-year is append-by-vintage, not incremental.

**`02a_resolve_cms_urls.py` resolves download URLs by stable dataset title.** CMS embeds per-release UUIDs in CDN paths that 404 on every new release; the resolver looks them up by stable title and writes `data_manifest.json`. ✅ Defensive engineering against an unstable upstream.

## C. Warehouse layout

**Two databases: `RAW` (landing) + `ANALYTICS` (dbt-built).** Hard separation of immutable source data from derived models — clean grants and blast radius. ✅ Standard medallion separation.

**One schema per dbt layer (`staging` / `intermediate` / `marts` / `seeds`), via a custom `generate_schema_name` macro.** `macros/generate_schema_name.sql` overrides dbt's default (which would prefix the target schema → `DBT_DEV_MARTS`) so the per-layer `+schema:` values are used verbatim — `ANALYTICS.STAGING`, `ANALYTICS.MARTS`, etc. — and the warehouse reads cleanly, matching the architecture diagram. ✅ Models without an explicit `+schema:` fall back to the sandbox schema in `profiles.yml`.

**Single `ANALYST` role for dbt + BI.** Simple single working role for a solo project. ⚙️ Production would split a write role (transformer) from a read-only role (reporter) for least privilege.

## D. dbt project structure & materialization

**Layered staging → intermediate → marts.** Staging = 1:1 cleaned source; intermediate = reusable business logic; marts = consumption. ✅ dbt Labs' recommended project structure.

**Staging = views; intermediate & marts = tables.** Views are free and always fresh for thin cleanup; the heavy aggregation/stats layers are tables so downstream reads are fast and don't recompute. ✅ Textbook materialization split. Intermediate is materialized (not ephemeral) because `int_provider__peer_group_stats` is reused downstream and is worth inspecting/testing on its own.

**Naming: `stg_` / `int_` / `fct_` / `dim_` / `mart_`, with double-underscore source grouping (`stg_part_d__prescriber_drug`).** Encodes layer + source + grain in the name. ✅ Standard dbt convention.

**`{{ source() }}` + `{{ ref() }}` throughout, with source freshness configured.** Full lineage and dbt-managed build order; freshness surfaces stale loads without failing builds. ✅

**NUCC taxonomy as a `seed` with pinned `column_types`.** Small, static, version-controlled reference data belongs in git; pinned types make the load deterministic. ✅

**Outlier math in `macros/` (`zscore`, `modified_zscore`, `is_outlier`).** Each is used 6× in the mart — one definition, one place to change, unit-testable. ✅ DRY.

**`require-dbt-version` pin + pinned packages + `package-lock.yml`.** The project depends on schema-yml shapes that changed across dbt 1.7→1.11; pinning makes builds reproducible and forces a deliberate major upgrade. ✅

## E. Data modeling

**A provider `dim` + two `fct`s (Part D, Part B) feeding one wide mart.** Keep dimensionally-clean facts for integrity; serve BI from a denormalized reporting mart. ⚙️ **It is a small star (one conformed `dim_provider`, two provider-year facts) plus a wide OBT (`mart_provider_outliers`), not a textbook star end-to-end.** The OBT is intentional: BI tools query one flat table fastest, and pre-joining peer stats avoids re-deriving them per query. Both Kimball (star) and modern dbt (OBT for serving) bless this combination.

**Natural key = NPI; no surrogate keys.** NPI is a stable, unique, government-issued 10-digit identifier — a genuinely good natural key. ⚙️ Surrogate keys (e.g. `dbt_utils.generate_surrogate_key`) become worthwhile once the grain goes multi-year (npi × year).

**Grain "provider × year," 2023 only → effectively one row per provider.** Scoped to one vintage; named `_provider_year` because the schema + loader are built to append vintages. 🔧 No trend analysis yet — documented in `README` limitations; multi-year is the next iteration.

**Filter to individuals (NPPES `entity_type = 1`, Part B `'I'`).** The peer-group analysis compares people within a specialty; org NPIs don't fit that frame. ⚙️ Deliberate scope (and part of why facility-aggregated NPIs surface as artifacts — see `findings.md` §1).

**Reconstruct Part B totals as `avg_per_service × services`, summed.** CMS publishes per-service *averages*, not totals; this is the only route to a provider-level total. ⚙️ Approximation by necessity, clearly commented. Transparency is built in: `total_beneficiaries_naive_sum` is explicitly named "naive" because summing per-HCPCS bene counts double-counts patients.

**Keep CMS-suppressed rows for cost/claims; drop only the unreliable beneficiary count.** Suppression nulls the *beneficiary* cell (<11 benes), not cost/claims — excluding the row would understate spend. The condition is surfaced via `is_beneficiary_count_suppressed`. ✅ Source-aware handling.

**`max_by(specialty, volume)` for a provider's representative specialty/geo.** A provider bills under several specialty/state strings; pick the one tied to their highest-volume row. ⚙️ Dominant-by-volume, deliberately — more defensible than raw mode for billing attribution. *(A code comment calls this "modal"; it is dominant-by-volume, not strict mode.)*

**Provider profile = union of all three sources + coverage flags; specialty/state via a documented fallback chain (NPPES → Part D → Part B).** One row per NPI regardless of source coverage, with NPPES preferred for identity/taxonomy. ✅ Clean conformed-dimension construction with explicit precedence.

## F. Methodology (statistical decisions)

**Peer group = NPPES taxonomy code × state, not CMS specialty text.** CMS text lumps ~116k providers into "Internal Medicine"; NPPES taxonomy splits that into cardiology / oncology / nephrology with 10×-different cost baselines. The switch cut the IM MAD-flag rate 45% → 31.8%. ✅ A measured methodology decision — *a peer group is only valid if members face the same economics.*

**`n ≥ 30` peer-group floor.** MAD and stddev are noisy on small samples — one large prescriber collapses MAD toward zero and makes everyone else look like a 10σ outlier. ✅ Conventional small-sample guardrail.

**Per-metric coverage gate (`peer_n_part_d ≥ 30`, etc.).** A peer group can clear the union `n ≥ 30` while having only a handful of actual Part D prescribers, leaving a Part D median computed on a thin subpopulation. Every flag is gated on ≥ 30 *observations of that metric*. ✅ A correctness fix found in the first cut and hardened with a singular test + unit test.

**Compute BOTH classical z-score and MAD modified-z.** Medicare spend is heavily right-skewed; the mean/stddev get dragged toward the very tails being detected, so z under-flags (2.01%) while MAD is robust (5.23%). Exposing both lets the consumer pick the threshold for their use case. ✅ Demonstrates *why* robust statistics exist.

**Thresholds |z| ≥ 2.0, |modified-z| ≥ 3.5, MAD constant 0.6745.** The 3.5 / 0.6745 pair is the published Iglewicz & Hoaglin convention (0.6745 calibrates MAD to be z-comparable under normality); 2.0 is the conventional z cut. All are tunable `{% set %}` knobs documented in `methodology.md` §6. ✅ Principled, not arbitrary.

**Two-pass MAD (window median, then `median(abs(x − group_median))`).** Snowflake can't nest `median()` in a single aggregate; pass 1 broadcasts the group median onto each row, pass 2 aggregates absolute deviations. ✅ Correct engine-aware workaround.

**Six metrics (3 Part D + 3 Part B), scored independently, OR-combined into `is_outlier_any_*`.** Cost, volume, and mix are different signals; "flag if any fires" maximizes recall for a triage list, while per-metric flags stay in the mart for precision filtering. ⚙️ Recall-oriented by design; a production scorer might weight metrics or require ≥ 2 to fire.

**`coalesce(flag, false)` in the composite.** A null score (stddev/MAD = 0 in a degenerate peer) shouldn't propagate an ambiguous flag — absence of evidence is "not flagged." ✅ Correct null handling, unit-tested.

**Exclude non-NPPES providers (inner join to peer stats).** No taxonomy → no valid peer group → can't be scored fairly. ⚙️ Drops ~150k of 7.21M providers (documented); excluding beats benchmarking against the wrong peers.

## G. Testing & orchestration

**Generic tests on keys (`unique` / `not_null` / `relationships`) + `accepted_values` on enums.** Enforce grain (one row per NPI), referential integrity (facts → dim), and domain validity (`drug_kind ∈ {brand, generic}`). ✅ The dbt testing baseline.

**Singular tests for business invariants** — brand share ∈ [0, 1]; overall MAD-flag rate < 8%; per-metric floor holds. Catch *logic* regressions schema tests miss (e.g. removing the coverage gate or swapping MAD for stddev would breach the 8% guardrail). ✅ Data-quality-as-regression-test.

**Unit tests on the mart with crafted rows** — prove the math (a large value fires; MAD = 0 → null → false; a sub-30 floor suppresses the flag) independent of warehouse data. ✅ Unit tests (dbt 1.8+) are advanced for a portfolio.

> Test inventory: **53 generic + 3 singular = 56 data tests**, plus **3 unit tests**. (dbt's manifest counts the 56 as `test` nodes and the 3 unit tests separately.)

**CI = offline `dbt parse` against a stub profile.** Validates SQL, `ref`/`source` lookups, and schema-yml on every push *without* putting Snowflake credentials in repo secrets. 🔧 CI does not build models or run data tests against a warehouse, so "all tests green" is a local claim. Parse catches the cheap, common breakages credential-free; running real tests needs a CI-scoped Snowflake key-pair user — the right next step out of portfolio mode.

**Orchestration: manual `dbt build` (Makefile); GitHub Actions only for parse + Pages deploy.** A solo, annual-cadence project doesn't need a scheduler. ⚙️ Productionizing = dbt Cloud or Airflow/Dagster on a cron, gated by `dbt source freshness`. The project is structured for it.

## H. Governance, ethics & docs

**Disclaimer ("outlier ≠ allegation") + a substantive Limitations section** (FFS-only, single year, cell suppression, self-reported taxonomy, facility attribution, not comparable to OIG methodologies). This is provider-level public data about named people — responsible framing is mandatory, not decoration. ✅ The facility-billing finding (top "individual" outliers are aggregated NPIs) is the model red-teaming its own output.

**Findings doc with reproducible SQL per claim.** Every headline number is traceable to a query against the marts. ✅ Reproducibility and credibility.

---

## Open items / next iterations

| Item | Type | Next step |
|---|---|---|
| CI runs `dbt parse` only | 🔧 | Provision a CI-scoped Snowflake key-pair user; run `dbt build` + tests on a sample. |
| Single vintage (CY 2023) | 🔧 | Load multiple `DY*` files; add year to the grain; enable trend/drift analysis. |
| Manual runs | ⚙️ | dbt Cloud or Airflow/Dagster schedule with freshness gating. |
| Single `ANALYST` role | ⚙️ | Split transformer (write) / reporter (read-only) roles for least privilege. |
| Natural NPI key | ⚙️ | Add surrogate keys when the grain becomes (npi × year). |
| State-level geography only | ⚙️ | Join HRR / HSA shapefiles for sub-state market peer groups. |
| OR-combined composite flag | ⚙️ | Weighted or ≥2-metric scoring for a precision-oriented variant. |
