# tools/crud — the feature-CRUD layer

The one write path for adding, renaming and removing a feature on the
**authored** layer. Architecture §18; operational contract `docs/plans/feature-crud.md`.

> A feature is a registry entry. Not a folder, not a Dart class. The entry is the
> identity; everything else is derived from it.

## What it writes (and what it never writes)

| layer | files | this tool |
|---|---|---|
| **authored** | `models/screens_model/registry.json`, `ui/views/<tab>/<short>/{_view.html,_viewmodel.js}`, `models/screens_model/migrations.json` (rename lineage, lazy) | **writes** |
| **generated** | `structure.json`, `lib/ui/views/**/*.dart` | **never** |

Editing generated output makes a second writer and kills the regenerate-and-diff
gate. Every surface that edits a feature — the desktop GUI, the chat, the
companion, `app-box-designer` — routes through this module so that nothing but
the pipeline's emitters touch the generated layer.

## Operations

```
python3 tools/crud/crud.py <op> <design-root> [flags]
```

| op | flags | behaviour |
|---|---|---|
| `list` | — | **Read.** The registry *is* the feature list (never a filesystem scan). |
| `show` | `id` | **Read** one entry. |
| `create` | `--id --tab --comp [--surface] [--label]` | Append entry + view pair. `--surface null` ⇒ entry only (a declared exclusion, no pair). Duplicate id is rejected (id is a stable key). |
| `update` | `--id [--label]` | Edit non-identity fields. `id`/`surface` are immutable on an entry. |
| `rename` | `--from --to [--surface]` | New id + explicit migration. The old pair is removed **only after** the new one exists (never delete-before-write). |
| `delete` | `--id --confirm TOK` | Remove entry + pair. **Behind a human-minted token** — the one operation that is not recoverable by re-running a stage. Idempotent on the desired end state. |
| `verify` | `[--fix --confirm TOK]` | Orphan sweep: a pair dir whose `surfaceId` maps to no live entry is a FAIL. `--fix` removes orphans (gated). |

`--root` is a design folder (contains `models/screens_model/`); it is passed in,
never hardcoded (R3).

## The delete gap this closes

The pipeline only writes. The coverage gate catches a surface claimed by no
scaffolded dir; it does **not** catch the reverse — a registry entry deleted while
its view pair lingers. This module closes that at the authored layer:

- **delete** removes the entry *and* its pair, and sweeps any orphan pair whose
  `surfaceId` is now dead.
- **verify** is the orphan assertion (§18) for the authored pair. The symmetrical
  assertion over scaffolded `lib/ui/views/` lives in `gates/coverage/` (see
  *Out of fence* below).
- A crash mid-delete (registry rewritten, pair not yet removed) is repaired by the
  next run: re-running `delete <id>` or `verify --fix` converges on the end state.

## The round-trip (the proof)

```
bash tools/crud/selftest.sh
```

The whole contract in one assertion: create a feature, delete it, and the tree
must be byte-identical to before the create. Asserted with
`git status --porcelain --untracked-files=all` inside a temp repo — R5's blessed
method, because a delete that leaves an untracked orphan file is the exact case
`git diff --exit-code` cannot see. The suite also checks no empty dirs survive
(porcelain cannot see those either).

Negative cases (R5 — every check can go red): duplicate id, no-confirm /
empty-confirm delete, an orphaned pair, a simulated crash mid-delete, and a guard
that CRUD never writes `structure.json` or `lib/**`.

## Wiring into the fixer

`crud.py` is the command surface the pipeline drives for feature mutations. The
delete is the operation that sits behind a human confirm (`--confirm`), matching
§18: the one fixer step that is not recoverable by re-running a stage. A run
mints the token at its gate (state `approvalTokens`), then invokes the op.

## Out of fence (reported, not done here)

- **Step 7.1 / Done-when #2** — the orphan assertion over scaffolded
  `lib/ui/views/<shell>/` belongs in `gates/coverage/`, owned by P04/P05 (the
  fence forbids touching `gates/`). The existing coverage gate already has a C2
  orphan check against the frozen surface map; once P05 makes `structure.json` a
  function of this registry, deleting an entry and re-emitting will surface as a
  frozen-surface/orphan-dir mismatch the gate already knows how to name.
- `tools/emit_structure/` is a stub today (P05, concurrent); the round-trip
  therefore proves the contract on the authored layer, which is the identity.
  Because `structure.json` is a pure function of the registry (§14), a
  byte-identical registry after the round-trip implies a byte-identical derived
  tree once the emitter lands.
