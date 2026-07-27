# structure

The STRUCTURE gate. Asserts `design/structure.json` (the shell/surface map)
**resolves**, is **in sync** with the authored registry, and has **no orphans
either way**. Split out of the vendored `freeze_design.sh` (plan 03) along the
render/structure seam. Findings route through `gates/_common/sarif.sh`.

## Asserts

- **S0 input** — `structure.json` is present and parses. Missing input FAILS
  (exit 1) — a gate that cannot find its input never passes quietly.
- **S1 drift** — when the producer source (`jsx/app.jsx`) is present,
  `structure.json` is regenerated and compared via `emit_structure --check`.
- **S2 resolve** — (a) every declared surface has a file; (b) every file is
  claimed by exactly one screen; (c) no surface is double-claimed; (d) the
  surface id sits under its shell prefix; (e) no tab root was left without a
  surface.

## Does not assert

- That the 6 frozen inputs exist or that surfaces render — freeze's job.
- Scaffold shape or coverage of the surfaces — scaffold/coverage's job.

## Run

```sh
structure.sh [app-root]                    # 0 pass / 1 FAIL / 2 env
KIT_DESIGN_DIR=design/new structure.sh
bash structure/selftest.sh                 # R5: happy + NEGATIVE cases
```
