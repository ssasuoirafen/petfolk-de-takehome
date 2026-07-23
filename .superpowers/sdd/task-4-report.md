# Task 4 Report: Silver Layer — Client Dedup + Visit-Level Model

## Summary

Task 4 completed successfully. All 4 intermediate layer models created exactly per specification. Build passes with expected warnings; verification counts match expected values.

## Implementation

### Files Created

1. **models/intermediate/int_client_id_map.sql** (8 lines)
   - Window function partitions stg_clients by email_hash and selects min(client_id) as canonical
   - Deduplicates same person appearing under multiple client_ids

2. **models/intermediate/int_clients.sql** (21 lines)
   - CTE aggregates int_client_id_map to count source_ids per canonical
   - Inner join to stg_clients to output canonical row with n_source_ids

3. **models/intermediate/int_visits.sql** (22 lines)
   - Left joins stg_appointments → int_client_id_map (handles 6 orphan clients)
   - Left joins to stg_patients for species
   - Outputs 300 rows with is_unknown_client flag for orphans (NULL canonical_client_id)

4. **models/intermediate/schema.yml**
   - int_client_id_map: [unique, not_null] on client_id; [not_null] on canonical_client_id
   - int_clients: [unique, not_null] on client_id
   - int_visits: [unique, not_null] on appointment_id; relationships test on client_id with `arguments:` nesting

## Verification (Step 5)

### Build
```
uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .
```
Result: `PASS=40 WARN=2 ERROR=0`
- 2 expected WARNs from Task 3 (patient-weight, orphan-clients relationships)
- 0 deprecation warnings
- All new tests pass (int_client_id_map, int_clients, int_visits)

### Counts
```
uv run --python 3.12 --with duckdb python -c "..."
```
| Model | Actual | Expected | Match |
|-------|--------|----------|-------|
| int_client_id_map (total, distinct canonicals) | (150, 144) | (150, 144) | ✓ |
| int_clients (total) | (144, None) | (144, None) | ✓ |
| int_visits (total, unknown-client) | (300, 6) | (300, 6) | ✓ |

## Commit

```
Commit: 5ddd36a
Message: feat: silver layer - client dedup and visit-level model
Files: 4 created (int_client_id_map.sql, int_clients.sql, int_visits.sql, schema.yml)
```

## Self-Review

✓ All files match brief specification exactly (verbatim SQL/YAML)
✓ UTF-8, trailing newlines present
✓ No typos or formatting issues
✓ YAML test nesting uses correct `arguments:` key
✓ Left join logic correctly handles 6 orphan clients
✓ Email_hash dedup logic preserves all relationships
✓ No unexpected files in git status
✓ Build result stable across multiple runs

## Concerns

None. Task complete per specification.
