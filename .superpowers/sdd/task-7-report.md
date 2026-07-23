# Task 7 Report: DECISIONS.md + README note + fresh-clone dry run

## Status: DONE

**Commit created:** 783b5a7 docs: decisions writeup and run notes

## Files Modified

- `DECISIONS.md`: Replaced template with full content (4 sections: Assumptions, How I handled the data issues, Trade-offs, What I would do differently in production)
- `README.md`: Appended "Candidate notes" section with instructions on PII masking and reference to DECISIONS.md

## Dry-Run Results (Step 3: Fresh-clone simulation)

### Step 3a: Ingest
```bash
rm -f petfolk.duckdb petfolk.duckdb.wal seeds/gladly_calls.csv
uv run --python 3.12 ingest_gladly.py
```
**Output:** `wrote 60 phone-call rows -> seeds/gladly_calls.csv`
**Expected:** 60-row CSV
**Result:** ✓ PASS

### Step 3b: Seed
```bash
uv run --python 3.12 --with-requirements requirements.txt dbt seed --profiles-dir .
```
**Output:** `Done. PASS=4 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=4`
**Expected:** PASS=4
**Result:** ✓ PASS

### Step 3c: Build
```bash
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
```
**Output:** `Done. PASS=55 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=57`
**Expected:** PASS=55, WARN=2 (1 orphan-clients relationships + 1 patient-weight outlier), ERROR=0
**Result:** ✓ PASS

**Row counts verified:**
- fct_visits: 173 rows ✓
- dim_clients: 144 rows ✓
- metric_revenue_per_visit: 87 rows ✓

## Masking Demo Test (Step 4)

```bash
uv run --python 3.12 --with duckdb python -c "..."
```

**Masked output (default):**
```
[('p***@example.com', '*******4582'), ('m***@example.com', '*******8744')]
```

**Unmasked output (with pii_role = 'unmask_pii_data'):**
```
[('parker.hall5@example.com', '+12302954582'), ('morgan.green17@example.com', '+19407848744')]
```

**Result:** ✓ PASS - Dynamic masking works correctly; same view shows masked/unmasked per session variable

## Git Verification (Step 5)

```bash
git status --short
```

**Output:**
```
 M DECISIONS.md
 M README.md
```

**Expected:** Only DECISIONS.md and README.md; no `.local/`, `petfolk.duckdb`, or `seeds/gladly_calls.csv`
**Result:** ✓ PASS - Clean workspace, only intended files modified

## Forward-Reference Resolution

Two code comments forward-reference DECISIONS.md:

1. **models/marts/fct_visits.sql:3** — "DECISIONS.md, including the one invoiced null-status row"
   - **Addressed by:** "Null statuses" bullet in DECISIONS.md (specifically mentions A0252, invoice 542.87, exclusion from fct_visits)
   - ✓ VERIFIED

2. **models/semantic/metric_revenue_per_visit.sql:9** — "Residual float display-rounding is documented in DECISIONS.md"
   - **Addressed by:** "revenue_per_visit" bullet in DECISIONS.md (explains double "/" division, $0.01 midpoint rounding, trade-off acceptance)
   - ✓ VERIFIED

## Commit Details

```
[main 783b5a7] docs: decisions writeup and run notes
 2 files changed, 32 insertions(+), 12 deletions(-)
```

Message: `docs: decisions writeup and run notes` (exactly as specified)

## Self-Review

- ✓ DECISIONS.md filled completely; no placeholder text remaining
- ✓ README.md appended with Candidate notes section
- ✓ Fresh-clone dry run fully green (60 CSV rows, seed PASS=4, build PASS=55 WARN=2 ERROR=0)
- ✓ Row counts correct (fct_visits=173, dim_clients=144, metric=87)
- ✓ Masking demo confirms dynamic query-time masking works
- ✓ Git status clean (only DECISIONS.md and README.md modified)
- ✓ Commit created with exact message
- ✓ Both forward-reference bullets present in DECISIONS.md
- ✓ UTF-8 no BOM, trailing newlines confirmed on both modified files

## No Concerns

All steps completed successfully. Submission-ready.

---

## Fix: Invoice-Null Count Correction

**Issue found by reviewer:** Line 12 of DECISIONS.md incorrectly stated "All 108 nulls" when the deduped staging layer has 107 nulls (one duplicated row with null invoice on both copies removes one upon dedup).

### Fix Applied

**Before:**
```
All 108 nulls sit on non-Completed rows; business-rule test asserts Completed => invoice present.
```

**After:**
```
All nulls (108 raw, 107 after dedup - one duplicated row was null on both copies) sit on non-Completed rows; business-rule test asserts Completed => invoice present.
```

### Verification

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute('select count(*) filter (invoice_total is null) from main_staging.stg_appointments').fetchall())"
```

**Output:** `[(107,)]`
**Expected:** `[(107,)]`
**Result:** ✓ PASS

### Git Status

```bash
git status --short
```

**Output:**
```
 M DECISIONS.md
```

**Result:** ✓ PASS - Only DECISIONS.md modified; UTF-8 no BOM + trailing newline maintained.

### Fix Commit

```
[main b025733] docs: correct invoice-null count for the deduped staging layer
 1 file changed, 1 insertion(+), 1 deletion(-)
```

**Commit message:** `docs: correct invoice-null count for the deduped staging layer` (exactly as specified)
**Result:** ✓ PASS

---

## Final-Review Fixes

### Changes Applied

**Change 1 — README.md:** Added candidate note before `## What's in the repo` heading
```
**Candidate note:** this submission adds a fourth seed. Run `python ingest_gladly.py` once before `dbt seed` (details in the Candidate notes section at the bottom).
```

**Change 2 — DECISIONS.md:** Precision on the "10 rows" claim
- **Before:** "the wrong order breaks 10 rows."
- **After:** "reading the dash format month-first would break 10 rows of that check."

**Change 3 — tests/assert_revenue_conserved_to_metric.sql:** New reconciliation test created
```sql
-- Reconciliation: the metric must carry exactly the revenue of fct_visits.
with fct as (
    select sum(invoice_total) as total_revenue from {{ ref('fct_visits') }}
),

metric as (
    select sum(revenue) as total_revenue from {{ ref('metric_revenue_per_visit') }}
)

select fct.total_revenue as fct_revenue, metric.total_revenue as metric_revenue
from fct, metric
where fct.total_revenue <> metric.total_revenue
```

### Commits

**Commit 1:** `2077dd5 docs: clarify seed generation order and datetime claim`
```bash
git add README.md DECISIONS.md && git commit -m "docs: clarify seed generation order and datetime claim"
```

**Commit 2:** `f799108 test: reconcile metric revenue with fct_visits`
```bash
git add tests/assert_revenue_conserved_to_metric.sql && git commit -m "test: reconcile metric revenue with fct_visits"
```

### Verification

```bash
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
```

**Output (final lines):**
```
Finished running 4 seeds, 2 table models, 44 data tests, 8 view models in 0 hours 0 minutes and 0.52 seconds (0.52s).

Completed with 2 warnings:

[[WARNING]]: in test assert_patient_weight_plausible (tests/assert_patient_weight_plausible.sql)
[[WARNING]]: Got 1 result, configured to warn if != 0

[[WARNING]]: in test relationships_stg_appointments_client_id__client_id__ref_stg_clients_ (models/staging/schema.yml)
[[WARNING]]: Got 6 results, configured to warn if != 0

Done. PASS=56 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=58
```

**Expected:** PASS=56 (+1 new test `assert_revenue_conserved_to_metric`), WARN=2 (orphan-clients + patient-weight), ERROR=0
**Result:** ✓ PASS

### Git Log

```bash
git log --oneline -3
```

**Output:**
```
f799108 test: reconcile metric revenue with fct_visits
2077dd5 docs: clarify seed generation order and datetime claim
b025733 docs: correct invoice-null count for the deduped staging layer
```

**Result:** ✓ PASS - Both new commits present on main

### Status: DONE
