# app_box — User-Flow Library

Production-grade user flows for every persona, per tab-group shell. Desktop UI
surfaces are built from these docs; a flow doc is complete when a developer can
build the screen flow from it without further design decisions.

Ground rules: vocabulary per [`architecture.md`](../../plans/architecture.md);
pipeline mechanics per §5–§6; decisions per §11–§18; research grounding in
[`research-findings.md`](research-findings.md); journeys in
[`../journeys/`](../journeys/) tell the per-persona narrative, this library
holds the mechanics.

## Layout

```
flows/<persona>/<tab-group-shell>/<flow-name>.md
```

- **Personas:** `evan-founder` (the operator — every surface is his), `michelle-buyer`
  (the evaluator — a subset of the same pipeline, read through a legibility
  filter).
- **Shells (tab groups):** `projects-shell`, `design-shell`, `build-shell`,
  `ship-shell`, `chat-shell`, `settings-shell`. Names follow the surface
  inventory in [`app-box-persona-design-brief.md`](../app-box-persona-design-brief.md)
  §10. One `stage_shell` hosts all six; the tab-group is the organising unit
  for flow docs, not a separate Flutter shell.
- **One file per flow** (a goal-oriented unit: `new-project.md`,
  `confirm-ship.md`, `run-build.md`). Scenario variants (offline, licence
  expired, red gate, stale render) are branches inside the flow, not separate
  files.

## Flow doc template

```markdown
# <Flow name>

Actor: <persona + role> · Shell: <tab-group> · Surfaces: <surface ids from the
brief §10 inventory, or "NEW — not yet scaffolded"> · Decision refs:
<architecture.md §, research doc>

## Trigger
What starts the flow (user action, system event, pipeline state change, deep
link).

## Entry / exit
- Entry criteria: state that must hold (pipeline phase, gate status, targets
  set, credentials configured).
- Exit states: every terminal state the flow can end in.

## Happy path
Numbered steps, one per screen-state transition. Name the Surface and its
states (from brief §10) at each step. Mark gate steps with **(Gate N)**.

## Decision points
Branches with their conditions and where each leads.

## Edge cases
Offline, gate red, licence expired, stale render, session expiry, partial
failure, empty/error states — each with its rendering. The licence check is a
precondition (💳), never a gate going red (architecture.md §17).

## Screens
Mapping table: step → surface/sheet/dialog (surface id from brief §10 or NEW
flag).

## Notes
Cross-references to sibling flows, architecture.md dependencies, flags, MEM-A
memory patterns.
```

## Conventions

- **Gate refs:** Gate 1 (design approve), Gate 2 (build accept), Gate 3 (ship
  confirm). Each is a human gate — an agent can reach it and stop, but cannot
  mint the approval token (`architecture.md` §12, §17). Mark gate steps
  **(Gate N)** in the happy path.
- **State names** per `architecture.md` §5–§6: the UI renders pipeline state
  from `work/` — `run.json` (stage → status, content_hash, outs, ts),
  `history.jsonl` (append-only transitions), `findings/*.sarif` (gate findings
  with `partialFingerprints`), `logs/*` (per-stage stdout+stderr). Never invent
  state names.
- **The licence precondition (💳)** runs before the builder phase, not as a
  gate. It fails with a licence message — never as red (`architecture.md` §17).
- **Red always means broken.** No flow shows red for payment, licence, or
  subscription reasons.
- **Stubs are labelled.** Flows touching `settings.kits` must show wired-vs-
  stubbed status. A kit that throws is never offered without a STUBBED label.
- **No state inferred from paint.** The companion FAB carries channel state
  (live / reconnecting / dead), driven by the paired channel's heartbeat —
  never by whether the WebView last painted (`architecture.md` §15).
- **Flows depending on a surface not yet scaffolded** carry
  `NEW — not yet scaffolded` in the Surfaces line and are listed in the
  persona's `_index.md`.
- **Each persona directory has an `_index.md`** listing its flows per shell.
