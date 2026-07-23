### Task 2: `ingest_gladly.py` → `seeds/gladly_calls.csv`

**Files:**
- Create: `ingest_gladly.py`

**Interfaces:**
- Consumes: `data/gladly_contacts.json` (`{pagination: {page, page_size, total}, conversations: [{conversation_id, customer: {id, phone}, items: [{contact_id, type, ...}]}]}`).
- Produces: `seeds/gladly_calls.csv`, header `conversation_id,contact_id,customer_phone,agent_id,started_at,duration_seconds`, one row per PHONE_CALL item (expected 60), sorted by (conversation_id, contact_id), missing duration → empty field. Task 3's `stg_gladly_calls` reads it via `ref('gladly_calls')`.

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env python3
"""Flatten the Gladly conversation export to one row per PHONE_CALL contact.

Reads data/gladly_contacts.json, writes seeds/gladly_calls.csv (a dbt seed).
Stdlib only. Idempotent: deterministic sort order, atomic overwrite.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "data" / "gladly_contacts.json"
OUT = ROOT / "seeds" / "gladly_calls.csv"
COLUMNS = [
    "conversation_id",
    "contact_id",
    "customer_phone",
    "agent_id",
    "started_at",
    "duration_seconds",
]
REQUIRED = ["conversation_id", "contact_id", "started_at"]


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not SRC.exists():
        fail(f"input file not found: {SRC}")
    try:
        payload = json.loads(SRC.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {SRC}: {exc}")

    conversations = payload.get("conversations")
    if not isinstance(conversations, list):
        fail("payload has no 'conversations' list")

    page = payload.get("pagination", {})
    total = page.get("total", len(conversations))
    if total > page.get("page", 1) * page.get("page_size", total):
        fail(
            f"export is paginated (total={total} > this page); "
            "refusing to write a partial extract"
        )

    rows: list[dict] = []
    problems: list[str] = []
    for conv in conversations:
        conv_id = conv.get("conversation_id")
        customer_phone = (conv.get("customer") or {}).get("phone")
        for item in conv.get("items", []):
            if item.get("type") != "PHONE_CALL":
                continue
            row = {
                "conversation_id": conv_id,
                "contact_id": item.get("contact_id"),
                "customer_phone": customer_phone,
                "agent_id": item.get("agent_id"),
                "started_at": item.get("started_at"),
                "duration_seconds": item.get("duration_seconds"),
            }
            missing = [k for k in REQUIRED if not row[k]]
            if missing:
                problems.append(f"{conv_id}/{row['contact_id']}: missing {missing}")
                continue
            duration = row["duration_seconds"]
            if duration is not None and (
                not isinstance(duration, int) or isinstance(duration, bool) or duration < 0
            ):
                problems.append(
                    f"{conv_id}/{row['contact_id']}: bad duration_seconds {duration!r}"
                )
                continue
            rows.append(row)

    if problems:
        fail("invalid phone-call items:\n  " + "\n  ".join(problems))

    contact_ids = [r["contact_id"] for r in rows]
    if len(contact_ids) != len(set(contact_ids)):
        fail("duplicate contact_id among phone calls")

    rows.sort(key=lambda r: (r["conversation_id"], r["contact_id"]))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_name(OUT.name + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: "" if row[k] is None else row[k] for k in COLUMNS})
    tmp.replace(OUT)
    print(f"wrote {len(rows)} phone-call rows -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it, verify row count**

Run: `uv run --python 3.12 ingest_gladly.py`
Expected: `wrote 60 phone-call rows -> seeds/gladly_calls.csv`

Run: `wc -l seeds/gladly_calls.csv`
Expected: `61` (header + 60 rows)

- [ ] **Step 3: Verify idempotency (byte-identical on rerun)**

```bash
shasum seeds/gladly_calls.csv && uv run --python 3.12 ingest_gladly.py && shasum seeds/gladly_calls.csv
```

Expected: identical checksum before/after.

- [ ] **Step 4: Verify dbt picks it up and empty durations land as NULL**

Run: `uv run --python 3.12 --with-requirements requirements.txt dbt seed --profiles-dir .`
Expected: `PASS=4` (four seeds, `gladly_calls` INSERT 60).

Run: `uv run --python 3.12 --with duckdb python -c "import duckdb; print(duckdb.connect('petfolk.duckdb').execute(\"select count(*), count(*) filter (duration_seconds is null or duration_seconds = '') from gladly_calls\").fetchall())"`
Expected: `[(60, 9)]`

- [ ] **Step 5: Verify the CSV is NOT tracked, then commit**

Run: `git status --short seeds/`
Expected: no `gladly_calls.csv` entry (gitignored).

```bash
git add ingest_gladly.py
git commit -m "feat: add Gladly phone-call ingestion script"
```

---

