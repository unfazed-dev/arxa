# Feature CRUD

How a feature is added, renamed and removed. Decision and rationale are
`architecture.md` §18; this is the operational contract.

## The one rule

**All CRUD writes the authored layer. Nothing writes generated output.**

| layer | files | who writes |
|---|---|---|
| **authored** | `models/screens_model/registry.json`, `ui/views/<shell>/<short>/{_view.html,_viewmodel.js}` | a person, the GUI, the chat, the companion |
| **generated** | `structure.json`, `surfaces/*.html`, `lib/ui/views/**/*.dart` | tools only |

Editing scaffolded Dart makes a second writer, and the regenerate-and-diff gate
loses anything to compare against. That gate is the only thing standing between
this pipeline and spec-driven development's documented failure — *authority by
convention rather than enforcement*.

**A feature is a registry entry.** Not a folder, not a Dart class. The entry is
the identity; everything else is derived from it.

## Create

1. Append to `registry.json`:
   ```json
   {"id":"inbox.thread_list","shell":"inbox","comp":"InboxThreadList",
    "surface":"stage_shell_thread_list_view","label":"Threads"}
   ```
2. Create `ui/views/<shell>/<short>/` with the `_view.html` + `_viewmodel.js`
   pair, and declare its identity in the viewmodel:
   ```js
   export const surfaceId = 'inbox.thread_list';
   ```
3. Re-emit surfaces → re-run freeze → scaffold emits the Dart.

`surfaceId` is what removes the fuzzy join: measured, only **21 of 37** frozen
screens resolved to a viewmodel by `(shell, short)` matching. A declaration takes
the residual to zero and turns a guess into an assertion.

## Read

`registry.json` **is** the feature list. Any UI listing features reads it —
never a filesystem scan, which is how the flat `registry: null` /
`shellRoots: {}` inference happened in the first place.

## Update

**Content or layout** — edit the pair, re-freeze. Nothing else moves.

**Rename — the dangerous one.** Downstream, a changed `id` is *delete plus
create*. So:

> **`id` is a stable key and is never reused.** A rename is a new `id` plus an
> explicit migration entry. Reusing an `id` for a different feature silently
> re-points every generated artifact that referenced it.

A `surface: null` entry is a **declared exclusion**, not a deletion — it stays
in the registry and is deliberately not frozen. This is already the kit's
convention and is why 42 registry entries produce 37 frozen screens.

## Delete — the gap, and its fix

**The pipeline only writes.** The coverage gate catches a surface claimed by no
screen. It does **not** catch the reverse: a scaffolded view directory whose
registry entry is gone. That orphan compiles, passes, and ships.

Two pieces, in order:

**1. The orphan assertion** — symmetrical with the existing coverage check:

> A directory under `lib/ui/views/<shell>/` that maps to no registry entry is a
> **FAIL**, naming the directory and the missing id.

Assert with `git status --porcelain` semantics, not `git diff` — a generator
that *adds* files is the expected case and `git diff` cannot see new files.

**2. The delete path in the fixer** — and it is the one fixer operation behind
a **human confirm**, because removing code is not recoverable by re-running a
stage.

Two prior failures constrain the design:

- A fixer that deleted before it wrote once left p2 with **no
  `app.locator.dart`**. Never delete before the replacement exists.
- Guard idempotence on the **desired end state**, never on "was this touched" —
  and explicitly delete paths that *older revisions* emitted, or renames leave
  debris that the orphan assertion will then flag forever.

## Where each surface performs CRUD

| surface | writes |
|---|---|
| desktop GUI feature list | `registry.json` |
| chat ("add a settings screen") | `registry.json` + scaffolds the pair |
| companion app | `registry.json` |
| `arxa-designer` | both authored layers |
| **anything** | never `structure.json`, never `lib/**` |

## Test that proves the rule holds

One test, and it is the whole contract:

> Create a feature, delete it, regenerate. The tree must be **byte-identical**
> to before the create. If deletion leaves anything behind, this fails.

Round-tripping is the only check that catches orphans, stale renames and
partial deletes in a single assertion — and it needs no fixtures.
