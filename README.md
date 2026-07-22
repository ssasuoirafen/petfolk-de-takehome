# Petfolk Senior Data Engineer: Take-Home Exercise

Expected time: about 2 to 3 hours. We do not expect 100 percent completion. We care more about clean judgment and documented decisions than about breadth.

You've joined Petfolk's data team. Two raw exports have landed, messy the way source data always is. Your job is to turn them into a small, trustworthy medallion pipeline that produces one governed metric: revenue per visit, by pet care center and month.

This runs entirely locally on `dbt-duckdb`. No cloud account, no cost.

## Setup

1. Create and activate a virtual environment using a Python 3.10 to 3.13 interpreter (dbt does not support 3.14 yet), for example `python3.12 -m venv .venv`.
2. Install dependencies: `pip install -r requirements.txt`
3. Load the raw data and confirm a green build:
   - `dbt seed --profiles-dir .`
   - `dbt build --profiles-dir .`

The dbt profile is bundled in `profiles.yml`, so pass `--profiles-dir .` on every dbt command. A local `petfolk.duckdb` file is created in the project root. Out of the box the three seeds load and `dbt build` runs green. You add models from there.

## What's in the repo

```
.
├── README.md
├── requirements.txt
├── dbt_project.yml
├── profiles.yml
├── DECISIONS.md            # fill this in
├── data/
│   └── gladly_contacts.json   # input for the Python task
├── seeds/                     # raw tables, loaded by `dbt seed`
│   ├── appointments_raw.csv
│   ├── clients_raw.csv
│   └── patients_raw.csv
├── models/
│   ├── staging/               # bronze
│   ├── intermediate/          # silver
│   ├── marts/                 # gold
│   └── semantic/              # metrics
├── tests/
└── macros/
```

Seeds load as all-VARCHAR on purpose, to mimic an untyped raw landing. All casting and cleanup is your job in the staging layer. The known issues are listed in the tables below.

### `appointments_raw.csv` (~300 rows)

| Column | Notes |
|---|---|
| `appointment_id` | Primary key. Contains duplicates. |
| `patient_id` | |
| `client_id` | Some values have no matching client. |
| `location_id` | |
| `appointment_type` | |
| `scheduled_at` | Mixed datetime formats. |
| `status` | Some nulls. |
| `provider_id` | |
| `invoice_total` | Dirty strings: dollar signs, commas, some nulls. |
| `created_at` | |

### `clients_raw.csv` (~150 rows)

| Column | Notes |
|---|---|
| `client_id` | Primary key. The same person can appear under more than one. |
| `first_name` | |
| `last_name` | |
| `email` | Pet-parent PII. Inconsistent casing. |
| `phone` | Pet-parent PII. |
| `location_id` | |
| `created_at` | |

### `patients_raw.csv` (~200 rows)

| Column | Notes |
|---|---|
| `patient_id` | Primary key. |
| `client_id` | Foreign key to clients. |
| `species` | |
| `breed` | |
| `date_of_birth` | |
| `sex` | |
| `weight_kg` | Some nulls and outliers. |

### `data/gladly_contacts.json`

A nested export of customer conversations. Each conversation holds a list of contact items, and only some are phone calls. This is the input for the Python task. The fields to extract are listed in Task 1.

## Tasks

1. **Python ingestion (about 30-45 min).** Write `ingest_gladly.py` that reads `data/gladly_contacts.json`, keeps only `PHONE_CALL` items, flattens each to one row, and writes `seeds/gladly_calls.csv` so dbt can pick it up as another seed. Run `dbt seed` again after you generate it. Make the script runnable, idempotent, and lightly validated. The output has one row per phone-call contact with these columns:
   - `conversation_id`
   - `contact_id`
   - `customer_phone` (pet-parent PII)
   - `agent_id`
   - `started_at`
   - `duration_seconds`

2. **dbt medallion build (about 60-90 min).**
   - Staging (bronze): one model per source, type-cast and cleaned. Parse `scheduled_at` to a real timestamp, convert `invoice_total` to numeric, standardize emails. Keep it 1:1 with the source.
   - Intermediate (silver): at least one conformed model. Resolve the duplicate-client problem here, and build a clean visit-level model joining appointments to clients and patients.
   - Gold (marts): `fct_visits` at one row per completed visit, plus one dimension of your choice.
   - Semantic (metrics): a model that exposes revenue per visit by location and month. This is the object BI and downstream consumers would read.

3. **Tests and docs (about 20-30 min).** Add dbt tests covering keys (`not_null`, `unique`), a `relationships` test from appointments to clients, `accepted_values` on status, and at least one test that encodes a business rule rather than boilerplate. Document the gold models and the metric in a `schema.yml`. `dbt build` should finish green.

4. **PII handling (about 10-15 min).** Decide how email and phone should be treated as data moves into the modeled layers. Implement one approach (exclude, mask, hash, tag, or isolate) and justify it in `DECISIONS.md`.

5. **DECISIONS.md.** A short writeup of your assumptions, how you handled each data issue, the trade-offs you accepted under the time budget, and what you would do differently in production on Snowflake with managed ingestion and orchestration. A template is included.

## Constraints

- This is built to take about three hours. Do not gold-plate. We value clean judgment and documented decisions over breadth.
- If you run short, prioritize a working end-to-end path from raw to the metric for appointments and clients, plus `DECISIONS.md`. Stub or note whatever you skip.
- AI tools are fine. Be ready to explain every line in the follow-up conversation.

## What to submit

A git repo or zip with your models, `ingest_gladly.py`, `DECISIONS.md`, and a short note on how to run anything beyond the standard steps. We will clone it, run your Python step, run `dbt seed` and `dbt build`, and expect green.

## Candidate notes

- Before the standard steps, generate the fourth seed: `python ingest_gladly.py`
  (stdlib only, no extra dependencies; rerun-safe). Then `dbt seed` / `dbt build`
  as above.
- PII (email, phone, customer_phone) is masked by default in all modeled layers.
  To see real values in a DuckDB session:
  `SET VARIABLE pii_role = 'unmask_pii_data';`
- Rationale for every data decision: `DECISIONS.md`.
