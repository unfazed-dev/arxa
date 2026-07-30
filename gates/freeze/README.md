# freeze

The FREEZE / PROTOTYPE gate. Asserts the frozen design inputs are present, the
design-approval stamp is valid, and every surface renders clean at **every
derived viewport** — the width set implied by `--targets` via
`pipeline/state/targets.derivation.json` (6.4). Widths come ONLY from
`config/app-box.config.json`; there are no viewport literals in the gate.

Split out of the vendored `freeze_design.sh` (plan 03) along the render/structure
seam: freeze owns *inputs + render + approval*; the structure gate owns the
shell/surface map. Findings route through `gates/_common/sarif.sh`.

## Two producer contracts (the producer-shape seam, dogfood P14 finding #1)

The gate branches on producer shape, detected by `app.routes.js` at the design
root (htmx) vs `surfaces/*.html` + `tokens.json` (stacked_kit):

- **stacked_kit producer** — frozen inputs `tokens.json`, `design-system.md`,
  `exclusions.json`, `direction-approved.md`, `brand-spec.md`, `structure.json`,
  `surfaces/*.html`. Rendered as files (each `surfaces/*.html` opened directly)
  via `uv run --with playwright`.
- **htmx producer (app-box-designer)** — frozen inputs `app.routes.js`,
  `structure.json`, the registry it points at, and `ui/views/**/*_view.html`.
  The views are Jinja templates, so they are **served by the designer's Node
  prototype server** (`skills/app-box-designer/runtime/serve.mjs`, loopback,
  OS-assigned port) and rendered via the runtime's Playwright
  (`render_htmx.mjs`). P09: the designer legitimately requires Node, so a
  dev-time gate MAY use it. Vocab/exclusions are N/A (no `tokens.json`); the
  clean-render check is the htmx analog.

Both paths preserve the **4.3 fix**: a fresh page per (surface/route, viewport),
so the console/page-error handler can never accumulate — each error is reported
exactly once.

## Asserts

1. **shape** — per producer (see above)
2. **approval (6.7)** — if `design/approval.lock` exists, the current targets +
   frozen-input hash must match the stamped ones; otherwise the approval is
   STALE and the gate fails loudly. `--approve` mints/refreshes the stamp. The
   input hash covers each producer's own frozen set.
3. **vocab** — [stacked_kit] `tokens.json` parses as DTCG and carries the kit
   token paths
4. **exclusions** — [stacked_kit] harness chrome signatures in surfaces are
   covered by `exclusions.json`
4b. **l10n** — [only when `<design>/l10n/` exists] every locale ARB carries
   exactly the `app_en.arb` template's key set (`@`-prefixed metadata ignored)
   and, per key, the same `{placeholder}` token set
5. **render** — headless Chromium loads every surface (stacked_kit: each
   `surfaces/*.html`; htmx: each GET route from `app.routes.js`) at every
   **derived** width with zero console/page errors; screenshots land under
   `.kit/state/prototype/evidence/`. When `<design>/l10n/` exists the htmx
   render adds a locale dimension: each route × viewport × locale (from the
   `app_*.arb` names, qps-ploc excluded) via `?lang=<locale>` on the route URL,
   locale stamped on the screenshot name

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
