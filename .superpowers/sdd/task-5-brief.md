### Task 5: Gold — `fct_visits` + `dim_clients` (+ docs)

**Files:**
- Create: `models/marts/fct_visits.sql`
- Create: `models/marts/dim_clients.sql`
- Create: `models/marts/schema.yml`

**Interfaces:**
- Consumes: `int_visits`, `int_clients`.
- Produces:
  - `fct_visits` (table) — one row per completed visit: `appointment_id, client_id, is_unknown_client, patient_id, species, location_id, provider_id, appointment_type, scheduled_at, visit_month date, invoice_total decimal`.
  - `dim_clients` (view — masked columns must stay dynamic): `client_id, first_name, last_name, email MASKED, phone MASKED, email_hash, phone_hash, location_id, created_at, n_source_ids`.

- [ ] **Step 1: Write `models/marts/fct_visits.sql`**

```sql
-- One row per completed visit. Null-status appointments are excluded: a visit
-- is only a visit once the source system marks it Completed (documented in
-- DECISIONS.md, including the one invoiced null-status row).
select
    appointment_id,
    client_id,
    is_unknown_client,
    patient_id,
    species,
    location_id,
    provider_id,
    appointment_type,
    scheduled_at,
    cast(date_trunc('month', scheduled_at) as date) as visit_month,
    invoice_total
from {{ ref('int_visits') }}
where status = 'Completed'
```

- [ ] **Step 2: Write `models/marts/dim_clients.sql`**

```sql
-- Kept as a VIEW on purpose: email/phone are masked dynamically per session;
-- a table would freeze whichever mask state existed at build time.
{{ config(materialized='view') }}

select
    client_id,
    first_name,
    last_name,
    email,
    phone,
    email_hash,
    phone_hash,
    location_id,
    created_at,
    n_source_ids
from {{ ref('int_clients') }}
```

- [ ] **Step 3: Write `models/marts/schema.yml`** (gold docs are a README task-3 requirement — full descriptions)

```yaml
version: 2

models:
  - name: fct_visits
    description: >
      One row per completed visit (status = Completed). Grain: appointment_id.
      Includes six visits whose client is absent from the clients export
      (client_id NULL, is_unknown_client = true): the revenue is real and the
      metric is location-based, so dropping them would understate revenue.
      Null-status appointments are excluded.
    columns:
      - name: appointment_id
        description: Visit grain, unique per completed visit.
        tests: [unique, not_null]
      - name: client_id
        description: >
          Canonical client id after duplicate resolution; NULL when the source
          referenced a client missing from the export.
        tests:
          - relationships:
              arguments:
                to: ref('dim_clients')
                field: client_id
      - name: location_id
        description: Pet care center where the visit happened (metric dimension).
        tests: [not_null]
      - name: visit_month
        description: Month of scheduled_at; the metric's time grain.
        tests: [not_null]
      - name: invoice_total
        description: Invoiced amount in USD, cleaned from raw strings.
        tests: [not_null]

  - name: dim_clients
    description: >
      One row per real person (144 after merging 6 duplicate id pairs on
      normalized email). email/phone are dynamically masked; set the session
      variable pii_role to the unmask role to see real values. Hashes are the
      stable identity keys.
    columns:
      - name: client_id
        tests: [unique, not_null]
      - name: n_source_ids
        description: How many raw client_ids merged into this person.
```

- [ ] **Step 4: Build and verify**

Run: `uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .`
Expected: green, fct_visits/dim_clients built as table/view respectively.

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute('select (select count(*) from main_marts.fct_visits), (select count(distinct appointment_id) from main_staging.stg_appointments where status = ''Completed''), (select count(*) from main_marts.dim_clients)').fetchall())"
```

Expected: first two numbers equal (~175, exact value from the query), third = 144.

Verify `dim_clients` is a view and `fct_visits` a table:

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute(\"select table_name, table_type from information_schema.tables where table_schema in ('main_marts')\").fetchall())"
```

Expected: `fct_visits` BASE TABLE, `dim_clients` VIEW.

- [ ] **Step 5: Commit**

```bash
git add models/marts/
git commit -m "feat: gold layer - fct_visits and dim_clients"
```

---

