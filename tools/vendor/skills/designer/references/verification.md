# Verification — Playwright screenshot + the conformance freeze gate

> Distilled from huashu's verification + ADR-0009's verifier-grounded refine loop. The Designer's
> output must **parse under the crew's deterministic stages** (the conformance gate), not just look
> good in a screenshot.

## Two checks, both mandatory
1. **Visual (Playwright)** — screenshot + console-error scan. Catches layout/interaction bugs the
   eye hides in code review.
2. **Conformance freeze gate** — the design parses under `capture_design`/`parse_jsx`, the
   `data_model.json` `seedFrom.map` validates, every screen mounts on `window.*` for `parity.py
   --all`, and the layer-check passes. This is what makes the output **reproducible**, not just pretty.

## Visual check — Playwright
```
npx playwright screenshot file:///path/to/design/Atlet.html out.png --viewport-size=1200,900
```
Or use the global install (`npm root -g` + `/playwright`). For multi-screen, screenshot each mounted
component (`window.Home`, `window.Detail`) via `parity.py --all` — it stands each up standalone with
hardcoded `SCREEN_PROPS` and screenshots it.

**Listen to `pageerror`:** a clean render has 0 console errors. A 404 on a shard, a Babel parse error,
a missing `window.*` mount — all surface as `pageerror`. Fix before handoff; don't ship a design that
errors on load.

## The conformance freeze gate (the reproducibility seam)
This is ADR-0009's verifier-grounded refine loop applied to the Designer's freeze step. The gate:

| Gate | Checks | On fail |
|---|---|---|
| **parse_jsx** | the shell + shards parse under React+Babel (the same parser `capture_design` uses) | repair the JSX; re-parse |
| **window-mount** | every `screenFlow` screen is on `window.*` with standalone-able props | add the `Object.assign(window, {...})`; re-check |
| **seedFrom.map** (Correction 1) | every map value ∈ `data.jsx` keys; every map key ∈ entity fields | fix the map; re-validate |
| **layer-check** | every entity traces to a design component; every data-expecting component has its entity | reconcile model ↔ JSX; re-check |
| **serverOnly vs seed** (Correction 4) | no seed projects onto a `serverOnly` column | re-target the seed map; re-check |
| **tokens coherence** | semantic tokens resolve to primitives; `--status-bar-bg` present if any dark screen; motion rise tokens complete or absent | fix tokens; re-check |
| **frontier coherence** | every `home_assets.dart` symbol has a JSX counterpart the design renders | reconcile; re-check |

**On any fail → repair → re-run.** Do not ship a design that fails the gate; the crew downstream
will either crash or silently produce a broken app. This is the freeze step: the LLM authors once,
the gate verifies, the output is frozen and replayed deterministically (ADR-0002).

## Pinned dependencies (no drift)
Use pinned React + Babel CDN versions (the same ones `capture_design` expects). Drift here = a
parse that worked today breaks tomorrow. Record the pinned versions in `design-system.md`. (If a
starter asset 404s or integrity-mismatches, check the pins first.)

## What "done" looks like
- ✅ Visual: screenshot(s) attached, 0 `pageerror`.
- ✅ Conformance: every gate green.
- ✅ `parity.py --all`: every screen mounts standalone and screenshots without null-reference.
- ✅ The frozen `design/` + `tokens.json` + `data_model.json` + `assets.jsx` + `home_assets.dart` +
  `design-system.md` are all present and mutually coherent.

A design that looks right but fails the gate is **not done** — it's a prototype, not a crew input.
