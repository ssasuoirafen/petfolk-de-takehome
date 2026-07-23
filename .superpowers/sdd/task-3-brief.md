### Task 3: Bronze — PII macros + 4 staging models + staging tests

**Files:**
- Create: `macros/pii.sql`
- Create: `models/staging/stg_appointments.sql`
- Create: `models/staging/stg_clients.sql`
- Create: `models/staging/stg_patients.sql`
- Create: `models/staging/stg_gladly_calls.sql`
- Create: `models/staging/schema.yml`
- Create: `tests/assert_scheduled_not_before_created.sql`
- Create: `tests/assert_completed_visits_have_invoice.sql`
- Create: `tests/assert_patient_weight_plausible.sql`
- Create: `tests/assert_call_duration_non_negative.sql`
- Modify: `dbt_project.yml` (models block — per-layer schema/materialization)

**Interfaces:**
- Consumes: seeds `appointments_raw`, `clients_raw`, `patients_raw`, `gladly_calls` via `ref()`.
- Produces (later tasks rely on these exact names/types):
  - macros: `mask_pii(column, kind)` (kind `'email'|'phone'`), `normalize_email(column)`, `normalize_phone(column)`, `hash_pii(column)`.
  - `stg_appointments(appointment_id varchar unique, patient_id, client_id, location_id, appointment_type, scheduled_at timestamp, status varchar nullable, provider_id, invoice_total decimal(10,2) nullable, created_at timestamp)` — deduped, 300 rows.
  - `stg_clients(client_id varchar unique, first_name, last_name, email varchar MASKED, phone varchar MASKED, email_hash varchar, phone_hash varchar, location_id, created_at timestamp)` — 150 rows.
  - `stg_patients(patient_id varchar unique, client_id, species, breed, date_of_birth date nullable, sex, weight_kg decimal(5,1) nullable)` — 200 rows.
  - `stg_gladly_calls(conversation_id, contact_id varchar unique, customer_phone varchar MASKED, customer_phone_hash varchar, agent_id, started_at timestamp, duration_seconds int nullable)` — 60 rows.

- [ ] **Step 1: Write `macros/pii.sql`**

```sql
-- PII helpers.
-- mask_pii: dynamic masking evaluated at query time. DuckDB has no roles, so the
-- "role" is a session variable: SET VARIABLE pii_role = '<unmask role>'.
-- Unset variable -> getvariable() returns NULL -> CASE falls through to the mask
-- (default-deny). In production this CASE body becomes a Snowflake masking policy.
{% macro mask_pii(column, kind='email') %}
    case
        when getvariable('pii_role') = '{{ var("pii_unmask_role", "unmask_pii_data") }}'
            then {{ column }}
        {% if kind == 'email' %}
        else regexp_replace({{ column }}, '^(.).*@', '\1***@')
        {% else %}
        else '*******' || right({{ column }}, 4)
        {% endif %}
    end
{% endmacro %}

{% macro normalize_email(column) %}
    lower(trim({{ column }}))
{% endmacro %}

-- Last 10 digits: collapses '+1XXXXXXXXXX' and 'XXXXXXXXXX' to the same key.
{% macro normalize_phone(column) %}
    right(regexp_replace({{ column }}, '[^0-9]', '', 'g'), 10)
{% endmacro %}

{% macro hash_pii(column) %}
    sha256({{ column }})
{% endmacro %}
```

- [ ] **Step 2: Write `models/staging/stg_appointments.sql`**

```sql
-- 1:1 with appointments_raw: typed, cleaned, exact-duplicate rows removed.
with deduped as (
    select *
    from {{ ref('appointments_raw') }}
    qualify row_number() over (
        partition by appointment_id
        order by created_at
    ) = 1
)

select
    appointment_id,
    patient_id,
    client_id,
    location_id,
    appointment_type,
    -- four source formats; shapes are mutually exclusive, so coalesce is safe:
    -- ISO Z, ISO space, day-first dash (DD-MM-YYYY), US month-first slash with AM/PM
    coalesce(
        try_strptime(scheduled_at, '%Y-%m-%dT%H:%M:%SZ'),
        try_strptime(scheduled_at, '%Y-%m-%d %H:%M:%S'),
        try_strptime(scheduled_at, '%d-%m-%Y %H:%M'),
        try_strptime(scheduled_at, '%m/%d/%Y %I:%M %p')
    ) as scheduled_at,
    status,
    provider_id,
    try_cast(replace(replace(invoice_total, '$', ''), ',', '') as decimal(10, 2))
        as invoice_total,
    strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') as created_at
from deduped
```

- [ ] **Step 3: Write `models/staging/stg_clients.sql`**

```sql
-- 1:1 with clients_raw. Raw email/phone never leave this layer unmasked:
-- masked columns for display, sha256 hashes of normalized values as identity keys.
select
    client_id,
    first_name,
    last_name,
    {{ mask_pii(normalize_email('email'), 'email') }} as email,
    {{ mask_pii('phone', 'phone') }} as phone,
    {{ hash_pii(normalize_email('email')) }} as email_hash,
    {{ hash_pii(normalize_phone('phone')) }} as phone_hash,
    location_id,
    strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') as created_at
from {{ ref('clients_raw') }}
```

- [ ] **Step 4: Write `models/staging/stg_patients.sql`**

```sql
-- 1:1 with patients_raw, typed. Weight outliers kept (flagged by a warn test);
-- nulls preserved.
select
    patient_id,
    client_id,
    species,
    breed,
    try_cast(date_of_birth as date) as date_of_birth,
    sex,
    try_cast(weight_kg as decimal(5, 1)) as weight_kg
from {{ ref('patients_raw') }}
```

- [ ] **Step 5: Write `models/staging/stg_gladly_calls.sql`**

```sql
-- 1:1 with the generated gladly_calls seed. customer_phone is pet-parent PII:
-- masked for display, hashed for identity. Missing durations stay NULL.
select
    conversation_id,
    contact_id,
    {{ mask_pii('customer_phone', 'phone') }} as customer_phone,
    {{ hash_pii(normalize_phone('customer_phone')) }} as customer_phone_hash,
    agent_id,
    strptime(started_at, '%Y-%m-%dT%H:%M:%SZ') as started_at,
    try_cast(duration_seconds as integer) as duration_seconds
from {{ ref('gladly_calls') }}
```

- [ ] **Step 6: Write `models/staging/schema.yml`**

```yaml
version: 2

models:
  - name: stg_appointments
    description: >
      Appointments typed and cleaned, 1:1 with the raw export minus exact
      duplicate rows. scheduled_at parsed from four source formats.
    columns:
      - name: appointment_id
        tests: [unique, not_null]
      - name: client_id
        description: >
          Six Completed appointments reference client ids absent from the
          clients export; kept on purpose (revenue is real), hence warn.
        tests:
          - not_null
          - relationships:
              to: ref('stg_clients')
              field: client_id
              config:
                severity: warn
      - name: patient_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_patients')
              field: patient_id
      - name: status
        description: Null for 9 raw rows; nulls are preserved in staging.
        tests:
          - accepted_values:
              values: ['Completed', 'Scheduled', 'Cancelled', 'NoShow']
      - name: scheduled_at
        tests: [not_null]

  - name: stg_clients
    description: >
      Clients 1:1 with raw. email/phone are dynamically masked; email_hash and
      phone_hash (sha256 of normalized values) are the join/dedup keys.
    columns:
      - name: client_id
        tests: [unique, not_null]
      - name: email_hash
        tests: [not_null]

  - name: stg_patients
    columns:
      - name: patient_id
        tests: [unique, not_null]
      - name: client_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_clients')
              field: client_id

  - name: stg_gladly_calls
    description: One row per PHONE_CALL contact from the Gladly export.
    columns:
      - name: contact_id
        tests: [unique, not_null]
      - name: conversation_id
        tests: [not_null]
      - name: started_at
        tests: [not_null]
```

- [ ] **Step 7: Write the four singular tests**

`tests/assert_scheduled_not_before_created.sql` (guards the datetime parsing — a wrong day/month parse breaks this ordering):

```sql
-- Business rule: an appointment cannot be scheduled before it was created.
select appointment_id, scheduled_at, created_at
from {{ ref('stg_appointments') }}
where scheduled_at < created_at
```

`tests/assert_completed_visits_have_invoice.sql`:

```sql
-- Business rule: every completed visit must have been invoiced.
select appointment_id
from {{ ref('stg_appointments') }}
where status = 'Completed' and invoice_total is null
```

`tests/assert_patient_weight_plausible.sql`:

```sql
-- Data quality: implausible weights flagged, not dropped (P0107 has 0.0 kg).
{{ config(severity='warn') }}
select patient_id, species, weight_kg
from {{ ref('stg_patients') }}
where weight_kg is not null and (weight_kg <= 0 or weight_kg > 120)
```

`tests/assert_call_duration_non_negative.sql`:

```sql
-- Business rule: call duration cannot be negative (null = unknown, allowed).
select contact_id, duration_seconds
from {{ ref('stg_gladly_calls') }}
where duration_seconds < 0
```

- [ ] **Step 8: Configure layers in `dbt_project.yml`** — replace the existing models block:

```yaml
models:
  petfolk_takehome:
    staging:
      +schema: staging
    intermediate:
      +schema: intermediate
    marts:
      +schema: marts
      +materialized: table
    semantic:
      +schema: semantic
      +materialized: table
```

(default `+materialized: view` on line 19 stays; dim_clients overrides back to view in Task 5 because masked columns must not be frozen into a table.)

- [ ] **Step 9: Build and verify**

Run: `uv run --python 3.12 --with-requirements requirements.txt dbt build --profiles-dir .`
Expected: green; 1 WARN (relationships stg_appointments.client_id, 6 orphans), 0 ERROR. `assert_patient_weight_plausible` warns (1 row, P0107).

Run row checks:

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); [print(r) for r in c.execute('select count(*) from main_staging.stg_appointments union all select count(*) filter (scheduled_at is null) from main_staging.stg_appointments union all select count(*) filter (invoice_total is null) from main_staging.stg_appointments').fetchall()]"
```

Expected: `(300,)`, `(0,)`, `(103,)` (108 raw nulls minus 5 duplicate rows removed; verify the exact number equals nulls on unique rows).

Masking spot-check (same session, variable toggling):

```bash
uv run --python 3.12 --with duckdb python -c "import duckdb; c = duckdb.connect('petfolk.duckdb', read_only=True); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall()); c.execute(\"set variable pii_role = 'unmask_pii_data'\"); print(c.execute('select email, phone from main_staging.stg_clients limit 1').fetchall())"
```

Expected: first row masked (`x***@example.com`, `*******NNNN`), second row real values.

- [ ] **Step 10: Commit**

```bash
git add macros/pii.sql models/staging/ tests/ dbt_project.yml
git commit -m "feat: bronze staging layer with dynamic PII masking and tests"
```

---

