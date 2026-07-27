# freeze

The FREEZE / PROTOTYPE gate. Asserts the frozen design inputs are present AND
that every surface renders clean at **every active viewport**
(`config/app-box.config.json` viewports — the active ladder widths).

Split out of the vendored `freeze_design.sh` (plan 03) along the render/structure
seam: freeze owns *inputs + render*; the structure gate owns the shell/surface
map. Findings route through `gates/_common/sarif.sh`.

## Asserts

1. **shape** — `tokens.json`, `design-system.md`, `exclusions.json`,
   `direction-approved.md`, `brand-spec.md`, `structure.json`, `surfaces/*.html`
2. **vocab** — `tokens.json` parses as DTCG and carries the kit token paths
3. **exclusions** — harness chrome signatures in surfaces are covered by
   `exclusions.json` (uncovered chrome would scaffold into kit UI)
4. **render** — headless Chromium loads every surface at every config viewport
   with zero console/page errors; screenshots land under
   `.kit/state/prototype/evidence/`

## Does not assert

- `structure.json` *resolution* (orphans, dangling surfaces) — that is the
  structure gate's job. Freeze only checks the file is present as a frozen input.
- Human/approval gates (direction, brand) beyond file presence.

## Run

```sh
freeze.sh [app-root]                       # 0 pass / 1 FAIL / 2 env
KIT_DESIGN_DIR=design/new freeze.sh        # producer folder (app-root-relative)
FREEZE_RENDER=skip freeze.sh …             # hermetic/non-browser runs
FREEZE_VIEWPORTS=mobile freeze.sh …        # restrict active widths (CI/test)
bash freeze/selftest.sh                    # R5: happy + NEGATIVE cases
```

## 4.3 — console-handler fix

The render loop uses a **fresh page per (surface, viewport)**, so the
console/pageerror handler can never accumulate across surfaces. Each error is
reported exactly once — the selftest asserts a one-error fixture across four
surfaces reports exactly one error (no ~4× inflation).
