# emit_structure

Derives `<app>/<design-dir>/structure.json` — the shell/surface map the FSM
intake contract never used to ask for.

```sh
tools/emit_structure/emit_structure.py --app <app-root> --design-dir design/new
tools/emit_structure/emit_structure.py --app <app-root> --design-dir design/new --check
tools/emit_structure/emit_structure.py --self-test
```

## Why it exists

`freeze_design.sh` used to require tokens, four docs and flat `surfaces/*.html`
and **nothing structural**. So every structural fact the scaffolder needs was
invented downstream:

| fact | where it came from before |
|---|---|
| which shell a surface belongs to | parsed out of the `<shell>_shell_` filename prefix — convention only, never asserted |
| which registry screens have no surface | nowhere; `emit_playground` silently skips `surface: null` |
| whether every surface on disk is claimed | `emit_playground --check` printed `note: orphan … left alone` and passed |

Then `shell_structure_gate.sh` and `review_checklist.sh` argued about the result
three phases later. `structure.json` moves those facts to the producer, where
they are known, and `freeze_design.sh` check 4 asserts them.

## Relationship to the sibling emitters

`emit_playground/` and `emit_htmx/` extract `window.P2.registry` through a
headless browser (`page.evaluate`), so they cannot run under `EMIT_RENDER=skip`.
`structure.json` is pure data and must be emittable with no playwright
installed, so this reads `jsx/app.jsx` as text instead. That also makes it
runnable *before* surfaces are emitted.

## Producer shapes

- **registry** — `jsx/app.jsx` has `P2_REGISTRY` + `P2_SHELL_ROOTS`. Every entry is
  emitted, `surface: null` included. Those nulls **are** the exclusions; there is
  no second "excluded" list, because a hand-maintained list is one you pad to
  keep a gate green.
- **surfaces** — no `jsx/`: one screen per `surfaces/*.html`, id/comp derived
  from the filename, empty `shellRoots`. (The htmx producer.)

`surfaces/index.html` is the playground harness page and is never a screen. That
name is hard-coded here and in the gate, not author-supplied, so a producer
cannot declare its way out of the coverage check.

## What check 4 asserts

resolution (declared surface has a file) · coverage (every file is claimed) ·
uniqueness (no two screens on one surface) · shell (matches the filename prefix)
· roots (no `shellRoots` entry left without a surface).

The last one is the one that catches a shell whose landing screen was designed but
never frozen. Adversarial twins live in `tools/test_gates.sh -g structure`.
