# Decisions

## Assumptions
- A "visit" is an appointment with status Completed; the metric covers completed visits only.
- Metric grain: pet care center (appointment's location_id, not the client's) x month of scheduled_at.
- All timestamps treated as UTC wall-clock; source offers no timezone info.
- The Gladly export is single-page (script fails loudly if pagination indicates otherwise). Its phones do not match any client phone, so calls stay a standalone seed rather than joining the medallion.

## How I handled the data issues
- Duplicate appointment IDs: 5 ids duplicated as exact full-row copies; kept first row per id (row_number over created_at). unique test guards the result.
- Mixed datetime formats in scheduled_at: four formats parsed via try_strptime coalesce chain. The two ambiguous ones have opposite day/month order - dash is day-first (46/76 raw rows have day > 12), slash is US month-first with AM/PM (46/78 raw rows have second part > 12, zero counterexamples). Cross-check: correct parsing keeps scheduled_at >= created_at on all 300 rows (encoded as a singular test); reading the dash format month-first would break 10 rows of that check.
- Dirty invoice_total strings: strip "$" and "," then cast decimal(10,2). All nulls (108 raw, 107 after dedup - one duplicated row was null on both copies) sit on non-Completed rows; business-rule test asserts Completed => invoice present.
- Null statuses: nine rows, preserved in staging (accepted_values ignores nulls), excluded from fct_visits. One null-status row carries an invoice (A0252) - not counted as a visit until the source confirms completion; revenue impact 542.87.
- Orphan client IDs: six Completed appointments (~4.9k USD) reference clients absent from the export. Kept in fct_visits with client_id NULL + is_unknown_client flag - the metric is location-based and dropping real revenue would understate it. relationships test at staging is severity warn to document the mismatch; strict at gold (nulls skipped).
- Duplicate clients: six pairs, same person under two ids (email differs at most by case, phone only by +1 prefix). Matched on sha256 of lower(trim(email)) - normalized phone yields identical pairs; names would over-merge (24 name-collision groups in the raw table, 20 of them across genuinely different people). Canonical = min(client_id); appointments remapped via int_client_id_map.
- PII (email, phone, customer_phone): dynamic masking. A macro wraps PII columns in a CASE on getvariable('pii_role'): sessions that set the unmask role variable see real values, everyone else (including dbt build and tests) sees masked ones. Join/dedup logic never touches maskable columns - it runs on sha256 hashes of normalized values, so build output is independent of session state. Masked columns live only in views (a table would freeze the mask state at build time - dim_clients stays a view for this reason). PII columns (including the hashes - pseudonymized data is still personal data) carry contains_pii meta and a pii tag in the yml, so tag-based policies and column-level lineage have an anchor to propagate from. Honest limit: DuckDB has no users/roles/grants, so locally this demonstrates the pattern rather than enforcing it - anyone can open the .duckdb file and read raw seeds. In production the same CASE body becomes a Snowflake masking policy bound to RBAC (see below).

## Trade-offs I accepted under the time budget
- No dbt packages (dbt_utils etc.): graders run only seed/build, not deps; built-in + singular tests cover the needs.
- No Python unit tests for ingest_gladly.py: it is stdlib-only, validated at runtime (schema, pagination, duplicates, durations) and verified by rerun-idempotency; a pytest suite would exceed the ingestion time box.
- Patient weight outliers flagged (warn test), not corrected: no defensible correction rule from this data alone, and weight does not feed the metric. Species-conditioned bounds were considered and rejected: weights in this export are not species-conditioned (cats reach 44.9 kg; 67 of 101 cats exceed any realistic cat limit), so per-species limits would flag a third of all patients - a systemic source-quality issue to raise upstream, not row-level outliers for a warn test.
- Gladly calls modeled to staging only: no fact/dim on calls because nothing links them to clients (zero phone overlap) and no metric requires them.
- Schemas main_staging/main_intermediate/... keep dbt's default prefix; renaming needs a generate_schema_name macro that adds no grading value.
- revenue_per_visit divides via DuckDB's double-returning "/" and then casts to decimal(10,2): on 1 of 87 location-months the persisted cent differs by $0.01 from exact decimal arithmetic (float representation of a true .485 midpoint rounds down). Accepted as display rounding - revenue and visit totals stay exact decimals - because exact integer-cents arithmetic would cost real readability. Would revisit if the metric fed billing rather than BI.

## What I would do differently in production
- Ingestion: managed EL (Fivetran/Airbyte) landing to raw schemas with loaded_at metadata; the Python step becomes an orchestrated task with retries, dead-letter handling and pagination support, not a hand-run script.
- Warehouse (Snowflake): raw layer locked to a loader role; masking via CREATE MASKING POLICY (same CASE body as the macro) attached to PII columns, unmasking granted through RBAC (e.g. IS_ROLE_IN_SESSION), tag-based policies to scale across columns.
- Orchestration: Airflow (or dbt Cloud jobs) running ingest -> seed/source freshness -> build -> test with alerting; environments (dev/CI/prod) with CI running slim builds (state:modified+) on PRs.
- Testing/governance: source freshness checks, contracts on gold models, unit tests for the parsing macro, data quality monitoring (e.g. elementary), and column-level lineage so PII tags propagate.
- Incremental models for fact tables once volume warrants it; seeds replaced by real sources.
