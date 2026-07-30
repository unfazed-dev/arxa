# structure

The STRUCTURE gate. Asserts `design/structure.json` (the shell/surface map)
**resolves**, is **in sync** with the authored registry, and has its exclusions
accounted for. The registry join (surfaceId → viewmodel), orphan detection and
shell derivation live in `tools/emit_structure/`; this gate asserts that output
is current and self-consistent. Findings route through `gates/_common/sarif.sh`.

## Asserts

- **S0 input** — `structure.json` is present and parses. Missing input FAILS
  (exit 1) — a gate that cannot find its input never passes quietly.
- **S1 drift** — no `jsx/app.jsx` guard: the check runs for every producer that
  carries the authored registry (`models/screens_model/registry.json`).
  - **S1a content** — `emit_structure --check` regenerates to memory and diffs
    against the on-disk file. Catches a one-char hand-edit, a stale registry, a
    missing `surfaceId`, an orphan viewmodel, or an empty `shellRoots` map.
  - **S1b tracked** — `git status --porcelain` over `structure.json` is empty.
    `git diff --exit-code` is forbidden here (R5): it cannot see an untracked
    file, and a producer that adds a surface is the expected case.
- **S2 resolve** — every shell root lands on a screen WITH a surface; the
  reconcile count is printed and the exclusion list (`surface: null`) is named,
  never silently dropped.

## Exclusion semantics

`surface: null` in the registry **is** the exclusion. There is no parallel
exclusions list — two ways to express one fact is the drift this architecture
exists to prevent. The count reconciles exactly:

```
registry entries == frozen screens (surface set) + exclusions (surface: null)
```

## Does not assert

- That the frozen inputs exist or that surfaces render — freeze's job.
- Scaffold shape or coverage of the surfaces — scaffold/coverage's job.

## Run

```sh
structure.sh [app-root]                       # 0 pass / 1 FAIL / 2 env
KIT_DESIGN_DIR=designs/app-box-app structure.sh
bash structure/selftest.sh                    # R5: happy + NEGATIVE cases
```
