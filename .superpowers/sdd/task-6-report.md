# Task 6: Semantic — revenue per visit by location and month

**Status:** DONE

## Commits

- `96ce2f6` feat: semantic layer - revenue per visit metric

## Files Created

1. `models/semantic/metric_revenue_per_visit.sql` — metric model with location_id, visit_month grain
2. `models/semantic/schema.yml` — documentation and tests for all columns
3. `tests/assert_metric_grain_unique.sql` — singular test ensuring grain uniqueness

## Verification Summary

**dbt build:** PASS=55 WARN=2 ERROR=0 (warnings are pre-existing, as expected)

**Data verification:**
```
Row count and month range:
[(87, datetime.date(2024, 1, 1), datetime.date(2025, 2, 1))]

Sample rows (first 5):
[('LOC01', datetime.date(2024, 1, 1), 3, Decimal('1887.12'), 629.04),
 ('LOC01', datetime.date(2024, 2, 1), 2, Decimal('1819.81'), 909.91),
 ('LOC01', datetime.date(2024, 3, 1), 1, Decimal('1352.00'), 1352.0),
 ('LOC01', datetime.date(2024, 4, 1), 1, Decimal('1007.00'), 1007.0),
 ('LOC01', datetime.date(2024, 5, 1), 1, Decimal('286.77'), 286.77)]
```

- **Row count:** 87 rows (✓ ≤ 112 expected max)
- **Month range:** 2024-01-01 to 2025-02-01 (✓ within 2024-01..2025-02)
- **revenue_per_visit values:** hundreds of USD (✓ 629.04, 909.91, 1352.0, 1007.0, 286.77)
- **Grain test:** PASS (no duplicates per location_id, visit_month)
- **NOT NULL tests:** PASS for location_id, visit_month, revenue_per_visit

## Implementation Notes

- Metric model groups fct_visits by (location_id, visit_month) computing visits (count), revenue (sum of invoice_total), revenue_per_visit (rounded to 2 decimals)
- Schema documentation covers all 5 columns with NOT NULL tests on the three grain/key columns
- Grain uniqueness test passes with zero violations
- No dbt config overrides needed; model lands as table in main_semantic as per dbt_project.yml routing

## Self-Review

✓ All file contents transcribed exactly from brief
✓ Build green with expected 2 pre-existing WARNINGs  
✓ Data sanity checks pass (month span, row count, revenue values)
✓ All tests pass including the new grain test
✓ Commit message matches brief exactly
✓ Only the three required files committed (verified git status)

## Type Pinning Fix

**Issue:** DuckDB's `/` operator on decimal operands returns DOUBLE; revenue_per_visit persisted as DOUBLE instead of the intended decimal type for the BI-facing contract.

**Fix Commit:** `966ecef` fix: pin revenue_per_visit to decimal(10,2) for the BI contract

**Change:**
```sql
-- Before:
round(sum(invoice_total) / count(*), 2) as revenue_per_visit

-- After:
-- DuckDB's "/" on decimals returns DOUBLE; cast pins the BI-facing type.
-- Residual float display-rounding is documented in DECISIONS.md.
cast(round(sum(invoice_total) / count(*), 2) as decimal(10, 2)) as revenue_per_visit
```

**Verification:**
- dbt build: PASS=55 WARN=2 ERROR=0
- Type check: `[('DECIMAL(10,2)', 87)]` — all 87 rows are DECIMAL(10,2) ✓
- Revenue sum invariant: True (metric sum equals fct_visits source) ✓
- Visit count total: 173 (matches all completed visits) ✓

## Concerns

None. Fix applied and verified; type contract now held.
