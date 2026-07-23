### Task 6: Semantic — revenue per visit by location and month

**Files:**
- Create: `models/semantic/metric_revenue_per_visit.sql`
- Create: `models/semantic/schema.yml`

**Interfaces:**
- Consumes: `fct_visits`.
- Produces: `metric_revenue_per_visit` (table) — one row per (location_id, visit_month): `location_id, visit_month, visits int, revenue decimal, revenue_per_visit decimal`. This is the BI-facing object.

- [ ] **Step 1: Write `models/semantic/metric_revenue_per_visit.sql`**

```sql
-- Governed metric: revenue per completed visit, by pet care center and month.
-- Numerator and denominator share one definition of "visit" via fct_visits.
select
    location_id,
    visit_month,
    count(*) as visits,
    sum(invoice_total) as revenue,
    round(sum(invoice_total) / count(*), 2) as revenue_per_visit
from {{ ref('fct_visits') }}
group by location_id, visit_month
```

- [ ] **Step 2: Write `models/semantic/schema.yml`** (metric docs — README task-3 requirement)

```yaml
version: 2

models:
  - name: metric_revenue_per_visit
    description: >
      Revenue per completed visit by pet care center and month. Grain:
      (location_id, visit_month). revenue = sum of cleaned invoice totals of
      completed visits; visits = count of completed visits; revenue_per_visit =
      revenue / visits. Months with zero completed visits have no row.
      Source of truth for BI and downstream consumers.
    columns:
      - name: location_id
        description: Pet care center (metric dimension).
        tests: [not_null]
      - name: visit_month
        description: Calendar month of the visits (metric time grain).
        tests: [not_null]
      - name: visits
        description: Completed visits in the location-month.
      - name: revenue
        description: Total invoiced USD for the location-month.
      - name: revenue_per_visit
        description: revenue / visits, rounded to cents.
        tests: [not_null]
```

- [ ] **Step 3: Add the metric grain test** — append to the same `schema.yml` a singular-style guarantee via a new file `tests/assert_metric_grain_unique.sql`:

```sql
-- The metric must be unique per (location_id, visit_month).
select location_id, visit_month, count(*) as n
from {{ ref('metric_revenue_per_visit') }}
group by location_id, visit_month
having count(*) > 1
```

- [ ] **Step 4: Build and verify**

Run: `uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .`
Expected: green.

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute('select count(*), min(visit_month), max(visit_month) from main_semantic.metric_revenue_per_visit').fetchall()); print(c.execute('select * from main_semantic.metric_revenue_per_visit order by location_id, visit_month limit 5').fetchall())"
```

Expected: months within 2024-01..2025-02, ≤ 8×14 rows, sane revenue_per_visit values (hundreds of USD).

- [ ] **Step 5: Commit**

```bash
git add models/semantic/ tests/assert_metric_grain_unique.sql
git commit -m "feat: semantic layer - revenue per visit metric"
```

---

