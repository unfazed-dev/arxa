# freeze

The FREEZE / PROTOTYPE gate. Asserts the frozen design inputs are present, the
design-approval stamp is valid, and every surface renders clean at **every
derived viewport** — the width set implied by `--targets` via
`pipeline/state/targets.derivation.json` (6.4). Widths come ONLY from
`config/app-box.config.json`; there are no viewport literals in the gate.

Split out of the vendored `freeze_design.sh` (plan 03) along the render/structure
seam: freeze owns *inputs + render + approval*; the structure gate owns the
shell/surface map. Findings route through `gates/_common/sarif.sh`.

## Asserts

1. **shape** — `tokens.json`, `design-system.md`, `exclusions.json`,
   `direction-approved.md`, `brand-spec.md`, `structure.json`, `surfaces/*.html`
2. **approval (6.7)** — if `design/approval.lock` exists, the current targets +
   frozen-input hash must match the stamped ones; otherwise the approval is
   STALE and the gate fails loudly. `--approve` mints/refreshes the stamp.
3. **vocab** — `tokens.json` parses as DTCG and carries the kit token paths
4. **exclusions** — harness chrome signatures in surfaces are covered by
   `exclusions.json` (uncovered chrome would scaffold into kit UI)
5. **render** — headless Chromium loads every surface at every **derived** width
   with zero console/page errors; screenshots land under
   `.kit/state/prototype/evidence/`

## Targets (6.2 / 6.3)

`targets` live in **pipeline state** (6.2). Gate + golden runs pass them
**explicitly** via `--targets` (6.3) so the snapshot is deterministic — ambient
state in a reproducibility run is the stale-green defect. With no `--targets`,
the gate reads them from pipeline state (the live SSOT). An unknown target, or
no targets at all, fails loudly.

## Does not assert

- `structure.json` *resolution* (orphans, dangling surfaces) — that is the
  structure gate's job. Freeze only checks the file is present as a frozen input.
- Human/approval gates (direction, brand) beyond file presence.

## Run

```sh
freeze.sh --targets macos [app-root]            # 0 pass / 1 FAIL / 2 env
freeze.sh --targets ios,android,web             # 3 derived widths
freeze.sh --targets macos --approve [app-root]  # mint/refresh approval.lock (6.7)
KIT_DESIGN_DIR=design/new freeze.sh …           # producer folder (app-root-relative)
FREEZE_RENDER=skip freeze.sh …                  # hermetic/non-browser runs
bash freeze/selftest.sh                         # R5: happy + NEGATIVE cases
```

## 4.3 — console-handler fix

The render loop uses a **fresh page per (surface, viewport)**, so the
console/pageerror handler can never accumulate across surfaces. Each error is
reported exactly once — the selftest asserts a one-error fixture across four
surfaces reports exactly one error (no ~4× inflation).
