# petfolk-de-takehome

Senior-DE take-home submission (dbt-duckdb medallion + Python ingestion). The git tree IS the deliverable - graders clone it, run `python ingest_gladly.py`, `dbt seed`, `dbt build`, and read DECISIONS.md closely. Everything below protects that.

## Hard rules

- AI use is publicly disclosed (2026-07-23): DECISIONS.md carries the disclosure section; this file, the plan (`.local/docs/plans/2026-07-22-petfolk-medallion.md`), and `.superpowers/sdd/task-*-{brief,report}.md` are tracked on purpose. Do not "re-hide" them.
- Still never commit: the rest of `.local/` (esp. `docs/handoff.md` - interview prep stays private - and `bin/`), the rest of `.superpowers/` (progress.md, review diffs), `.claude/`, `petfolk.duckdb*`, `seeds/gladly_calls.csv` (graders regenerate it). The committed `.gitignore` is the only safety net (`.git/info/exclude` is empty), and it covers just `.local/`, `petfolk.duckdb*`, `seeds/gladly_calls.csv`, `.claude/memory/`, `.claude/settings.local.json`, `.mcp.json`, `CLAUDE.local.md`; the tracked plan under `.local/docs/plans/` survives that because `.gitignore` never untracks what is already in the index. The rest of `.claude/` (a new `settings.json`, skills) and all of `.superpowers/` are not ignored and surface as untracked - stage by path, never `git add -A`.
- Committed artifacts must work through the graders' pip path: `requirements.txt` is the interface - no pyproject/uv.lock, no new Python deps, `ingest_gladly.py` stays stdlib-only (bare Python 3.10-3.13).
- No dbt packages (`packages.yml`): graders run only seed/build, never `dbt deps`.

## Tooling (local)

- Python via uv only: `uv run --python 3.12 --with-requirements requirements.txt dbt <cmd> --profiles-dir .`
- dbt always from repo root with `--profiles-dir .` (bundled profile, relative duckdb path).
- DB browsing: `.local/bin/duckdb-1.5.4 -ui -cmd "attach 'petfolk.duckdb' as petfolk (read_only);"` - pinned CLI because brew's 1.5.5 has no published `ui` extension yet (delete the binary once `INSTALL ui` works there). A globally `-readonly` session breaks the UI's state catalog. Any open UI/CLI session holds a lock on the db - close it before `dbt build`.

## Conventions

- Expected green state: `dbt build` with 0 errors, exactly 2 deliberate WARNs (orphan-client relationships at staging, patient-weight plausibility), zero deprecation warnings. Generic tests with args nest them under `arguments:` (dbt 1.12).
- Layers: staging (1:1 typed) -> intermediate (dedup/conform) -> marts -> semantic. Data numbers/counts live in DECISIONS.md - don't restate them here or in docs.
- Conventional commits on `main`; git identity already set locally (personal GitHub noreply).

## PII invariants (do not regress)

- `email`, `phone`, `customer_phone` appear in modeled layers only masked (`mask_pii`) or hashed (`hash_pii`); raw values exist only in seeds.
- Maskable columns live in VIEWS only - a table freezes mask state at build time (why `dim_clients` overrides marts' table default).
- Joins/dedup run on hashes, never on masked columns - build output must not depend on session state.
- Unmask demo: `SET VARIABLE pii_role = 'unmask_pii_data';` (role name configurable via dbt var `pii_unmask_role`).
- Tests must never assert raw PII values.

## Submission

Submitted: public at https://github.com/ssasuoirafen/petfolk-de-takehome (`gh auth switch ssasuoirafen` before pushing). Never zip/push the working folder wholesale - untracked local artifacts would leak. Open items and interview-prep pointers: `.local/docs/handoff.md` (local-only).
