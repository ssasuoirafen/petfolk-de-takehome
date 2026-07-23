# Task 5 Report: Gold Layer - fct_visits + dim_clients

## Status
**DONE**

## Files Created
1. `models/marts/fct_visits.sql` - Fact table of completed visits
2. `models/marts/dim_clients.sql` - Dimension view of clients (with dynamic PII masking)
3. `models/marts/schema.yml` - Documentation and tests

## Build Verification

### Build Result
```
Completed with 2 warnings:
PASS=50 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=52
```

Expected state: 2 WARNs remain (both expected and pre-existing):
- `assert_patient_weight_plausible`: 1 result
- `relationships_stg_appointments_client_id__client_id__ref_stg_clients_`: 6 results

**Result:** ✅ Build green, expected 2 warnings confirmed

### Row Counts
```
fct_visits count:              173
distinct completed appointments: 173
dim_clients count:              144
```

**Result:** ✅ Counts match exactly

### Table Types (information_schema.tables)
```
dim_clients: VIEW
fct_visits: BASE TABLE
```

**Result:** ✅ Table types correct (dim_clients VIEW preserves dynamic masking, fct_visits TABLE as grain table)

## Commit

```
Commit: 56b117f
Message: feat: gold layer - fct_visits and dim_clients
Files: 3 changed, 77 insertions(+)
  - create mode 100644 models/marts/dim_clients.sql
  - create mode 100644 models/marts/fct_visits.sql
  - create mode 100644 models/marts/schema.yml
```

## Self-Review

### SQL Correctness
- ✅ `fct_visits.sql`: Filters to `status = 'Completed'`, projects exact output contract (11 columns)
- ✅ `dim_clients.sql`: Config materialized='view', projects masking columns as-is from int_clients (no PII processing—masking is session-based)
- ✅ Tests use `arguments:` nesting (no deprecation warnings)

### Output Contract Verification
fct_visits columns match Task 6 requirement exactly:
- appointment_id, client_id, is_unknown_client, patient_id, species, location_id, provider_id, appointment_type, scheduled_at, visit_month (date), invoice_total (decimal)

dim_clients grain and structure confirmed:
- 144 rows (6 duplicate id pairs merged)
- NULL client_ids from unknown-client visits in fct_visits are allowed (relationships test permits NULL)

### Test Coverage
- ✅ fct_visits: unique+not_null on appointment_id, relationships (allows NULL), not_null on location_id/visit_month/invoice_total
- ✅ dim_clients: unique+not_null on client_id

### Known State Preserved
- ✅ 2 WARNs remain (weight plausibility + 6 unknown-client relationships)
- ✅ Zero deprecation warnings
- ✅ No unexpected dbt config warnings

## Concerns
None. All verifications pass, output contract matches downstream requirements, and table/view materialization preserves the intended masking semantics.

---

## Documentation Fix (Post-Review)

**Issue:** Initial schema.yml documented only 5 of 11 fct_visits columns and 2 of 10 dim_clients columns.

**Fix:** Added complete column-level descriptions for all 11 fct_visits and 10 dim_clients columns (no new tests added, existing test count = 8 preserved).

### Build Verification After Fix
```
Completed with 2 warnings:
PASS=50 WARN=2 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=52
```

- ✅ Build green, same result as before
- ✅ Deprecation warnings: 0 (grep -ci deprecat logs/dbt.log)
- ✅ Test count unchanged: 8 tests in gold models (6 fct_visits + 2 dim_clients)

### Fix Commit
```
Commit: ea58bcb
Message: docs: complete column-level documentation for gold models
Files: 1 changed, 29 insertions(+)
  - models/marts/schema.yml
```

**fct_visits columns now documented:**
- appointment_id, client_id, is_unknown_client (new), patient_id (new), species (new), location_id, provider_id (new), appointment_type (new), scheduled_at (new), visit_month, invoice_total

**dim_clients columns now documented:**
- client_id (added description), first_name (new), last_name (new), email (new), phone (new), email_hash (new), phone_hash (new), location_id (new), created_at (new), n_source_ids
