# data_model.json — the canonical structure (Tier 2, paired with data.jsx)

> The crew's latest inversion (ADR-0012): **structure in `data_model.json`, seed VALUES in
> `data.jsx`**, joined by `seedFrom.map`. The Designer authors **both**, internally consistent.
> `blueprint.py` projects `data_model.json` → Supabase migrations + `seed.sql` + Drift schema +
> repository Ports. This is the contribution no source skill has.

## The schema (mirror `blueprint.py`'s exact expectations)
```json
{
  "entities": [
    {
      "name": "session",                 // → Drift class name, lowerCamelCase
      "table": "sessions",                // → Supabase/Drift table name
      "orderBy": "occurred_on",           // optional: default sort column
      "fields": [
        {"name": "id",          "type": "uuid", "pk": true, "default": "gen_random_uuid()"},
        {"name": "user_id",     "type": "uuid", "owner": true, "serverOnly": true,
         "notNull": true, "references": "auth.users"},
        {"name": "title",       "type": "text", "notNull": true},
        {"name": "metric",      "type": "int",  "notNull": true},
        {"name": "occurred_on", "type": "date", "notNull": true},
        {"name": "created_at",  "type": "timestamptz", "serverOnly": true, "default": "now()"}
      ],
      "seedFrom": {
        "source": "SEED_WORKOUTS",                   // window.* global in data.jsx
        "map":   {"title": "name", "metric": "target", "unit": "unit",
                  "note": "notes", "streak": "streak"},
        "date":  {"column": "occurred_on", "from": "last", "anchor": "2026-06-23"}
      }
    }
  ],
  "authUser": { "id": "a71e7000-…", "email": "test@atlet.app", "password": "password123" }
}
```

## Field flags (what each does downstream)
| Flag | Meaning | Effect |
|---|---|---|
| `pk: true` | primary key | Drift PK; migration PK |
| `owner: true` | the owning user | RLS policy `auth.uid() = <col>`; owner-derived |
| `references: "auth.users"` | FK to Supabase auth | migration FK; owner-link |
| `serverOnly: true` | server-computed only | **excluded from Drift** (no client column); seed projection here crashes the Drift shadow |
| `default: "<sql>"` | DB default | migration `DEFAULT <sql>`; if omitted on a pk, `gen_random_uuid()` |
| `notNull: true` | non-null constraint | migration `NOT NULL`; Drift non-nullable |
| `seed: [{...}]` | inline seed rows | direct seed values (use for owner/profile rows tied to `authUser`) |
| `seedFrom: {…}` | projected seed | maps `data.jsx` arrays → rows (use for content rows) |

`seed` vs `seedFrom`: use `seed` for the one row tied to `authUser` (the profile); use `seedFrom`
for content arrays (`SEED_WORKOUTS`). An entity has one or the other, not both.

## Correction 1 — the `seedFrom.map` coherence rule (the freeze gate)
The map is **bidirectionally exact** or the seed silently nulls → broken DB:
- Every map **value** (RHS) ∈ `data.jsx` keys of the `source` array. (atlet: `name`/`target`/`unit`/
  `notes`/`streak` all exist in `SEED_WORKOUTS`.)
- Every map **key** (LHS) ∈ the entity's `fields` names. (atlet: `title`/`metric`/`unit`/`note`/
  `streak` are all session fields.)
- A single typo'd RHS → the seed row gets null for that column. A single typo'd LHS → the column is
  never populated. Both are silent.

**The freeze gate validates both directions.** Re-author on fail; do not patch.

## Correction 4 — `serverOnly` vs seed collision
A seed row projecting onto a `serverOnly` column crashes the Drift shadow (the column doesn't exist
client-side). The freeze gate rejects any `seedFrom.map` whose value would land in a `serverOnly`
field. Author seed maps that target only client-visible columns; let `serverOnly` columns be
DB-computed (`default`, `now()`).

## The layer-check (entity ↔ component trace — the other freeze gate)
Every entity must trace to a **design component** the UI actually renders, and vice versa:
- An entity with no UI binding (hallucinated) → the build has a table no screen reads. Halt.
- A UI component expecting an entity that isn't in the model → the screen nulls at runtime. Halt.

Author `data_model.json` by walking the design: each list/detail/form component that shows persisted
data → an entity. The home list → the content entity; the profile header → the owner entity.

## `authUser` — the seed user (operator, not Designer-derived)
`authUser` provides the `auth.users` row the seed `owner` columns reference. Its **id** is the
`owner`/`references auth.users` value; its **email/password** are seeded for the test/dev user.
**Secrets stay in env** (ADR-0004/0008): the `authUser` here is the reproducible dev seed, not a
production credential. `SUPABASE_*` env vars, project-ref, MCP connection → operator/env, never the model.

## Not Designer outputs (the clean line)
- `SUPABASE_*` env, project-ref, MCP connection → operator/env.
- Capability toggles (`offlineSync`, etc.) → operator config.
- Production credentials → env (the model's `authUser` is the dev/test seed only).
