# Task 3 Implementation Report

## Summary
Successfully implemented Task 3: Bronze staging layer with 4 staging models, PII masking macros, schema validation, and singular tests.

## Files Implemented

### Macros
- **macros/pii.sql** (35 lines)
  - `mask_pii(column, kind)` - Dynamic query-time masking with session variable `pii_role`
  - `normalize_email(column)` - Lowercase and trim
  - `normalize_phone(column)` - Extract last 10 digits (regex strips non-numeric)
  - `hash_pii(column)` - SHA256 hashing for identity keys

### Staging Models
1. **models/staging/stg_appointments.sql** (32 lines)
   - Deduplicates appointments_raw by appointment_id (removes 5 exact-duplicate rows)
   - Parses scheduled_at from 4 source formats (ISO Z, ISO space, day-first dash, US month-first)
   - Casts invoice_total to decimal(10,2) after stripping $ and commas
   - Preserves null status and null invoice_total values
   - Output: 300 rows (305 raw - 5 duplicates)

2. **models/staging/stg_clients.sql** (13 lines)
   - 1:1 with clients_raw (150 rows)
   - Applies mask_pii to email (email kind) and phone (phone kind)
   - Hashes normalized email/phone as identity keys (email_hash, phone_hash)
   - Parses created_at from ISO Z format

3. **models/staging/stg_patients.sql** (11 lines)
   - 1:1 with patients_raw (200 rows)
   - Casts date_of_birth to date, weight_kg to decimal(5,1)
   - Preserves nulls (weight outliers kept, flagged by warn test)

4. **models/staging/stg_gladly_calls.sql** (12 lines)
   - 1:1 with gladly_calls seed (60 rows)
   - Masks customer_phone (phone kind) and hashes normalized value
   - Parses started_at from ISO Z format
   - Casts duration_seconds to integer, preserves nulls

### Schema and Tests
- **models/staging/schema.yml** (66 lines)
  - Generic tests: unique, not_null, relationships (with warn severity on orphan clients), accepted_values
  - Describes each model and column with business context
  - Notes data quality issues (e.g., 6 orphan client_ids, 9 null statuses, 1 implausible weight)

- **tests/assert_scheduled_not_before_created.sql** - Verifies scheduled_at >= created_at
- **tests/assert_completed_visits_have_invoice.sql** - Verifies Completed appointments have invoice_total
- **tests/assert_patient_weight_plausible.sql** - Warns on weight <= 0 or > 120 kg (severity: warn, 1 row: P0107)
- **tests/assert_call_duration_non_negative.sql** - Verifies duration_seconds >= 0

### Configuration
- **dbt_project.yml** modified
  - Added layer-specific schema assignments (staging, intermediate, marts, semantic)
  - Added materialization overrides (marts and semantic as table, others as view)
  - Preserved default +materialized: view for backward compatibility

## Verification Results

### Step 9: dbt build
```
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
```
**Result:** GREEN
- Completed with 2 warnings (expected 2)
- PASS=29 WARN=2 ERROR=0 SKIP=0
- Tests passed: all generic tests, all 4 singular tests
- Warnings:
  1. `assert_patient_weight_plausible` - 1 row (P0107 with 0.0 kg weight)
  2. `relationships_stg_appointments_client_id` - 6 rows (orphan client IDs: revenue-bearing but missing from clients export)

### Row Counts
```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); [print(r) for r in c.execute('select count(*) from main_staging.stg_appointments union all select count(*) filter (scheduled_at is null) from main_staging.stg_appointments union all select count(*) filter (invoice_total is null) from main_staging.stg_appointments').fetchall()]"
```
**Result:**
- (300,) - stg_appointments row count
- (0,) - null scheduled_at (all parsed successfully)
- (107,) - null invoice_total (108 raw nulls - 1 duplicate removed)

**Note:** Brief specified "103 expected", but actual is 107. Analysis shows:
- Raw appointments_raw: 305 total, 108 with null invoice_total
- Duplicates: A0005 (null,null), A0015, A0042, A0067, A0149 (all have invoice amounts)
- After dedup: 300 total, 107 with null (108 - 1 removed null)
- Calculation verified: this is correct for the current seed data

### Masking Spot-Check
```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall()); c.execute(\"set variable pii_role = 'unmask_pii_data'\"); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall())"
```
**Result:** Masking working correctly
- Masked row: `[('p***@example.com', '*******4582')]`
  - Email: first letter + *** + @ + domain
  - Phone: 7 asterisks + last 4 digits
- Unmasked row (after setting pii_role): `[('parker.hall5@example.com', '+12302954582')]`
  - Returns original values

### Other Row Counts Verified
- stg_clients: 150 rows (1:1 with clients_raw)
- stg_patients: 200 rows (1:1 with patients_raw)
- stg_gladly_calls: 60 rows (1:1 with gladly_calls seed)

## Commit
```
Commit: 82f8bad
Message: feat: bronze staging layer with dynamic PII masking and tests
Files: 11 changed, 186 insertions
```

Files committed:
- macros/pii.sql
- models/staging/stg_appointments.sql
- models/staging/stg_clients.sql
- models/staging/stg_patients.sql
- models/staging/stg_gladly_calls.sql
- models/staging/schema.yml
- tests/assert_scheduled_not_before_created.sql
- tests/assert_completed_visits_have_invoice.sql
- tests/assert_patient_weight_plausible.sql
- tests/assert_call_duration_non_negative.sql
- dbt_project.yml (modified)

## Self-Review

✓ All files transcribed exactly as specified in the brief (SQL, YAML, macros)
✓ dbt build green with expected 2 warnings
✓ Row counts correct (deduplication working, parsing correct)
✓ PII masking verified (dynamic masking, session variable control)
✓ All tests passing (generic + 4 singular)
✓ Git status clean after staging and commit
✓ Commit message follows conventional commits
✓ No unexpected files in commit
✓ No secrets or sensitive data in committed files
✓ UTF-8, trailing newlines verified in all files

## Notes
- Deprecation warning about relationships test arguments (4 occurrences) - this is dbt v1.12 warning about future syntax, not an error; tests work correctly
- Unused configuration paths warning for intermediate, marts, semantic layers - expected (they don't have models yet; will be used in later tasks)
- Invoice total null count differs from brief's "103 expected" - analysis confirms 107 is correct for current seed data

## Fix Section (Post-Review)

### Finding 1: Generic Test Argument Nesting (dbt 1.12 Deprecation)

**Issue:** Schema.yml had 4 test blocks with `arguments` at the root level instead of nested under `arguments:`, triggering MissingArgumentsPropertyInGenericTestDeprecation warnings.

**Fix Applied:**
Modified `models/staging/schema.yml` to nest all generic test arguments under `arguments:` with `config:` as a sibling:

Changes:
1. Line 17-21: stg_appointments.client_id relationships - added `arguments:` wrapper, kept `config:` sibling
2. Line 25-29: stg_appointments.patient_id relationships - added `arguments:` wrapper
3. Line 31-35: stg_appointments.status accepted_values - added `arguments:` wrapper
4. Line 56-59: stg_patients.client_id relationships - added `arguments:` wrapper

### Finding 2: Email Masking Fail-Open Guard

**Issue:** `regexp_replace` returns its input unchanged on no match (e.g., malformed email without '@'), which would leak raw PII through the masked branch.

**Fix Applied:**
Modified `macros/pii.sql` email branch to guard the regex replacement:
```
when {{ column }} like '%@%'
    then regexp_replace({{ column }}, '^(.).*@', '\1***@')
else '***'
```

This ensures malformed emails (without '@') fall through to the '***' mask instead of leaking.

### Verification (All Three Required Tests)

**1. dbt build — Deprecation Warning Check:**
```bash
rm logs/dbt.log  # Clear old log
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
grep -c "Deprecation" logs/dbt.log
```
**Result:** 0 deprecation warnings found
- Build completed with PASS=29 WARN=2 ERROR=0
- Both warnings are expected data issues (not deprecations):
  - assert_patient_weight_plausible: 1 row (P0107 @ 0.0 kg)
  - relationships_stg_appointments_client_id: 6 rows (orphan client IDs)

**2. Email Masking Guard Test:**
```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect(); print(c.execute(\"select case when 'not-an-email' like '%@%' then regexp_replace('not-an-email', '^(.).*@', 'X***@') else '***' end, case when 'a@b.com' like '%@%' then regexp_replace('a@b.com', '^(.).*@', 'X***@') else '***' end\").fetchall())"
```
**Result:** `[('***', 'X***@b.com')]`
- Malformed email (no '@'): correctly returns '***'
- Valid email ('a@b.com'): correctly masks to 'X***@b.com'

**3. stg_clients Masking Spot-Check (Re-verify):**
```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print('Masked (default):'); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall()); c.execute(\"set variable pii_role = 'unmask_pii_data'\"); print('Unmasked (after pii_role):'); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall())"
```
**Result:**
- Masked: `[('p***@example.com', '*******4582')]`
- Unmasked: `[('parker.hall5@example.com', '+12302954582')]`
- Status: Working correctly ✓

**4. Schema YAML Argument Blocks:**
```bash
grep -n "arguments:" models/staging/schema.yml
```
**Result:** 4 occurrences (lines 18, 27, 34, 57) ✓
- All nesting now correct
- dbt parsed without errors ✓

### Fix Commit
```
Commit: f8b70d3
Message: fix: nest generic test args per dbt 1.10+ and guard email mask fail-open
Files: 2 changed, 16 insertions, 8 deletions
```

## Status
All findings fixed and verified. Deprecation warnings eliminated. PII guard working. Ready for next task (Task 4: Intermediate layer).
