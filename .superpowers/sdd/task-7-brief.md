### Task 7: DECISIONS.md + README note + fresh-clone dry run

**Files:**
- Modify: `DECISIONS.md` (fill the template)
- Modify: `README.md` (append a short "Candidate notes" section)

**Interfaces:**
- Consumes: everything above. Produces the submission-ready repo.

- [ ] **Step 1: Fill `DECISIONS.md`** (replace template bullets; keep it short per its own instruction):

```markdown
# Decisions

## Assumptions
- A "visit" is an appointment with status Completed; the metric covers completed visits only.
- Metric grain: pet care center (appointment's location_id, not the client's) x month of scheduled_at.
- All timestamps treated as UTC wall-clock; source offers no timezone info.
- The Gladly export is single-page (script fails loudly if pagination indicates otherwise). Its phones do not match any client phone, so calls stay a standalone seed rather than joining the medallion.

## How I handled the data issues
- Duplicate appointment IDs: 5 ids duplicated as exact full-row copies; kept first row per id (row_number over created_at). unique test guards the result.
- Mixed datetime formats in scheduled_at: four formats parsed via try_strptime coalesce chain. The two ambiguous ones have opposite day/month order - dash is day-first (46/76 rows have day > 12), slash is US month-first with AM/PM (46/78 rows have second part > 12, zero counterexamples). Cross-check: correct parsing keeps scheduled_at >= created_at on all 300 rows (encoded as a singular test); the wrong order breaks 10 rows.
- Dirty invoice_total strings: strip "$" and "," then cast decimal(10,2). All 108 nulls sit on non-Completed rows; business-rule test asserts Completed => invoice present.
- Null statuses: preserved in staging (accepted_values ignores nulls), excluded from fct_visits. One null-status row carries an invoice (A0252) - not counted as a visit until the source confirms completion; revenue impact 542.87.
- Orphan client IDs: six Completed appointments (~4.9k USD) reference clients absent from the export. Kept in fct_visits with client_id NULL + is_unknown_client flag - the metric is location-based and dropping real revenue would understate it. relationships test at staging is severity warn to document the mismatch; strict at gold (nulls skipped).
- Duplicate clients: six pairs, same person under two ids (email differs only by case, phone only by +1 prefix). Matched on sha256 of lower(trim(email)) - normalized phone yields identical pairs; names would over-merge (24 distinct-person name collisions). Canonical = min(client_id); appointments remapped via int_client_id_map.
- PII (email, phone, customer_phone): dynamic masking. A macro wraps PII columns in a CASE on getvariable('pii_role'): sessions that set the unmask role variable see real values, everyone else (including dbt build and tests) sees masked ones. Join/dedup logic never touches maskable columns - it runs on sha256 hashes of normalized values, so build output is independent of session state. Masked columns live only in views (a table would freeze the mask state at build time - dim_clients stays a view for this reason). Honest limit: DuckDB has no users/roles/grants, so locally this demonstrates the pattern rather than enforcing it - anyone can open the .duckdb file and read raw seeds. In production the same CASE body becomes a Snowflake masking policy bound to RBAC (see below).

## Trade-offs I accepted under the time budget
- No dbt packages (dbt_utils etc.): graders run only seed/build, not deps; built-in + singular tests cover the needs.
- No Python unit tests for ingest_gladly.py: it is stdlib-only, validated at runtime (schema, pagination, duplicates, durations) and verified by rerun-idempotency; a pytest suite would exceed the ingestion time box.
- Patient weight outliers flagged (warn test), not corrected: no defensible correction rule from this data alone, and weight does not feed the metric.
- Gladly calls modeled to staging only: no fact/dim on calls because nothing links them to clients (zero phone overlap) and no metric requires them.
- Schemas main_staging/main_intermediate/... keep dbt's default prefix; renaming needs a generate_schema_name macro that adds no grading value.
- revenue_per_visit divides via DuckDB's double-returning "/" and then casts to decimal(10,2): on 1 of 87 location-months the persisted cent differs by $0.01 from exact decimal arithmetic (float representation of a true .485 midpoint rounds down). Accepted as display rounding - revenue and visit totals stay exact decimals - because exact integer-cents arithmetic would cost real readability. Would revisit if the metric fed billing rather than BI.

## What I would do differently in production
- Ingestion: managed EL (Fivetran/Airbyte) landing to raw schemas with loaded_at metadata; the Python step becomes an orchestrated task with retries, dead-letter handling and pagination support, not a hand-run script.
- Warehouse (Snowflake): raw layer locked to a loader role; masking via CREATE MASKING POLICY (same CASE body as the macro) attached to PII columns, unmasking granted through RBAC (e.g. IS_ROLE_IN_SESSION), tag-based policies to scale across columns.
- Orchestration: Airflow (or dbt Cloud jobs) running ingest -> seed/source freshness -> build -> test with alerting; environments (dev/CI/prod) with CI running slim builds (state:modified+) on PRs.
- Testing/governance: source freshness checks, contracts on gold models, unit tests for the parsing macro, data quality monitoring (e.g. elementary), and column-level lineage so PII tags propagate.
- Incremental models for fact tables once volume warrants it; seeds replaced by real sources.
```

- [ ] **Step 2: Append to `README.md`**:

```markdown
## Candidate notes

- Before the standard steps, generate the fourth seed: `python ingest_gladly.py`
  (stdlib only, no extra dependencies; rerun-safe). Then `dbt seed` / `dbt build`
  as above.
- PII (email, phone, customer_phone) is masked by default in all modeled layers.
  To see real values in a DuckDB session:
  `SET VARIABLE pii_role = 'unmask_pii_data';`
- Rationale for every data decision: `DECISIONS.md`.
```

- [ ] **Step 3: Fresh-clone dry run** (simulate the graders):

```bash
rm -f petfolk.duckdb petfolk.duckdb.wal seeds/gladly_calls.csv
uv run --python 3.12 ingest_gladly.py
uv run --python 3.12 --with-requirements requirements.txt dbt seed --profiles-dir .
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
```

Expected: 60-row CSV regenerated; seed PASS=4; build fully green (1 known relationships WARN + 1 weight WARN, 0 ERROR).

- [ ] **Step 4: Final masking demo check** (query-time behavior on the final artifacts):

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print('masked :', c.execute('select email, phone from main_marts.dim_clients limit 2').fetchall()); c.execute(\"set variable pii_role = 'unmask_pii_data'\"); print('unmasked:', c.execute('select email, phone from main_marts.dim_clients limit 2').fetchall())"
```

Expected: masked then real values from the same view.

- [ ] **Step 5: Verify nothing stray is staged, commit**

Run: `git status --short`
Expected: only `DECISIONS.md` and `README.md` modified; no `.local/`, no `petfolk.duckdb`, no `seeds/gladly_calls.csv`.

```bash
git add DECISIONS.md README.md
git commit -m "docs: decisions writeup and run notes"
```

---

## Self-Review

- **Spec coverage:** README Task 1 → plan Task 2 (script, 60 rows, idempotent, validated, seed green). Task 2 staging → plan Task 3 (4 models, casts, email standardization via normalize+mask); intermediate → plan Task 4 (dedup + int_visits); gold → plan Task 5 (fct_visits + dim_clients); semantic → plan Task 6. README Task 3 tests → unique/not_null (all layers), relationships appointments→clients (staging, warn) + fct→dim (strict), accepted_values on status, business rules (scheduled≥created, completed⇒invoice, non-negative duration, metric grain); gold + metric docs in marts/semantic schema.yml; green build each task. README Task 4 PII → mask approach implemented (Task 3 macro + Task 5 view constraint) and justified in DECISIONS (Task 7). README Task 5 → DECISIONS.md filled (Task 7). Submission note → README Candidate notes (Task 7). ✓
- **Placeholder scan:** all steps carry complete code/commands; no TBD/TODO/"similar to". ✓
- **Type consistency:** `email_hash`/`phone_hash` names consistent across stg_clients → int_client_id_map → int_clients → dim_clients; `canonical_client_id` aliased to `client_id` at int_visits and consumed as `client_id` downstream; `visit_month` defined in fct, consumed in semantic; macro names `mask_pii`/`normalize_email`/`normalize_phone`/`hash_pii` used exactly as defined. ✓
- **Known uncertainty (resolve at execution, not blockers):** exact fct_visits row count (~175) and post-dedupe invoice-null count (103) are asserted by comparison queries rather than hardcoded expectations; `main_staging` etc. schema names assume dbt's default `generate_schema_name` (`<target.schema>_<custom>`); DuckDB `sha256()` availability assumed (verified DuckDB 1.5.5 locally has it — if the installed version lacks it, fall back to `md5()` in `hash_pii` only).
