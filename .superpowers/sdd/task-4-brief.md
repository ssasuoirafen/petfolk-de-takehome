### Task 4: Silver — client dedup + visit-level model

**Files:**
- Create: `models/intermediate/int_client_id_map.sql`
- Create: `models/intermediate/int_clients.sql`
- Create: `models/intermediate/int_visits.sql`
- Create: `models/intermediate/schema.yml`

**Interfaces:**
- Consumes: `stg_appointments`, `stg_clients`, `stg_patients` (Task 3 shapes).
- Produces:
  - `int_client_id_map(client_id varchar unique — all 150, canonical_client_id varchar)` — 144 distinct canonicals.
  - `int_clients` — one row per canonical client (144 rows), same columns as `stg_clients` plus `n_source_ids int`.
  - `int_visits` — one row per unique appointment (300 rows): `appointment_id, client_id (canonical, NULL for orphans), source_client_id, is_unknown_client boolean, patient_id, species, location_id, appointment_type, scheduled_at, status, provider_id, invoice_total, created_at`.

- [ ] **Step 1: Write `models/intermediate/int_client_id_map.sql`**

```sql
-- Same person can appear under several client_ids. Cluster on the hash of the
-- normalized email (names collide across distinct people; normalized phone
-- produces the same 6 pairs and stays available as a cross-check).
-- Canonical id = lowest client_id in the cluster (created_at ties in all pairs).
select
    client_id,
    min(client_id) over (partition by email_hash) as canonical_client_id
from {{ ref('stg_clients') }}
```

- [ ] **Step 2: Write `models/intermediate/int_clients.sql`**

```sql
-- One row per real person: the canonical row's attributes.
with map as (
    select canonical_client_id, count(*) as n_source_ids
    from {{ ref('int_client_id_map') }}
    group by canonical_client_id
)

select
    c.client_id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    c.email_hash,
    c.phone_hash,
    c.location_id,
    c.created_at,
    map.n_source_ids
from {{ ref('stg_clients') }} as c
inner join map
    on c.client_id = map.canonical_client_id
```

- [ ] **Step 3: Write `models/intermediate/int_visits.sql`**

```sql
-- Visit-level conformed model: every unique appointment, client ids remapped to
-- canonical. Six Completed appointments reference clients missing from the
-- export: client_id becomes NULL (flagged), the visit and its revenue stay.
select
    a.appointment_id,
    m.canonical_client_id as client_id,
    a.client_id as source_client_id,
    m.canonical_client_id is null as is_unknown_client,
    a.patient_id,
    p.species,
    a.location_id,
    a.appointment_type,
    a.scheduled_at,
    a.status,
    a.provider_id,
    a.invoice_total,
    a.created_at
from {{ ref('stg_appointments') }} as a
left join {{ ref('int_client_id_map') }} as m
    on a.client_id = m.client_id
left join {{ ref('stg_patients') }} as p
    on a.patient_id = p.patient_id
```

- [ ] **Step 4: Write `models/intermediate/schema.yml`**

```yaml
version: 2

models:
  - name: int_client_id_map
    description: Maps every raw client_id to its canonical (deduplicated) id.
    columns:
      - name: client_id
        tests: [unique, not_null]
      - name: canonical_client_id
        tests: [not_null]

  - name: int_clients
    description: One row per real person after duplicate-id resolution.
    columns:
      - name: client_id
        tests: [unique, not_null]

  - name: int_visits
    description: >
      Visit-level model, one row per unique appointment, all statuses. Client
      ids are canonical; orphan client references are NULL with
      is_unknown_client = true.
    columns:
      - name: appointment_id
        tests: [unique, not_null]
      - name: client_id
        tests:
          - relationships:
              arguments:
                to: ref('int_clients')
                field: client_id
```

- [ ] **Step 5: Build and verify counts**

Run: `uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .`
Expected: green (same 2 known WARNs from Task 3, no new ones, zero deprecation warnings).

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); [print(r) for r in c.execute('select count(*), count(distinct canonical_client_id) from main_intermediate.int_client_id_map union all select count(*), null from main_intermediate.int_clients union all select count(*), count(*) filter (is_unknown_client) from main_intermediate.int_visits').fetchall()]"
```

Expected: `(150, 144)`, `(144, None)`, `(300, 6)`.

- [ ] **Step 6: Commit**

```bash
git add models/intermediate/
git commit -m "feat: silver layer - client dedup and visit-level model"
```

---

