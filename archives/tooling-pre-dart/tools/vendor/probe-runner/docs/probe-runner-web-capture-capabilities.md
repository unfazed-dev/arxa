# probe-runner — Web-Capture Capability Reference

What the content-free web-capture path emits today, by feature. Every field below
is **mechanism-only** (ids/roles/layout/sizing/computed-style maps/token refs/
lengths) — never page content. The single invariant is
`content_firewall.audit_bundle(dir) == []`, re-run as a backstop inside
`bundle_writer`, `site_capture`, `site_chrome`, and `site_merge`. The audit is
**content-based, not key-based**: it text-scans every non-binary bundle file for
prose/urls/base64/magic-bytes, so a new field that carried content is caught
regardless of its name.

Provenance `§` refers to sections of `docs/plans/probe-runner-engine-capture-gaps.md`.

## Per-node skeleton fields (`skeleton.json` → `nodes[]`)

| Field | Feature | Producer | Provenance |
|---|---|---|---|
| `role`,`bbox`,`font`,`z`,`sizing`,`layout`,`parent` | Base content-free skeleton (REST DOMSnapshot) | `web_skeleton._snapshot_skeleton` | §B / §C9 |
| `substrate` | Render-substrate class (canvas/svg/img/dom/video) | `web_skeleton.classify_substrate` | §C9-R-P2 (G5/G9/G11) |
| `aria_role` | ARIA landmark role (fixed allowlist; IP boundary — no author `role=` text reaches disk) | `web_skeleton.apply_aria_roles` | §C9-R-aria |
| `token_ref` | Nearest-palette token reference per node | `bundle_writer.apply_token_refs` | §C9-R / G3b basis |
| `style` | Regime-1 per-node visual computed-style map | `bundle_writer.apply_node_style` → `_style.redact_node_styles` | §C9-R-P6 / P7 |
| `pseudo` | Regime-2 `::before`/`::after`/`::marker` map: content-free style + content + own `bbox` geometry (`w>0 ∧ h>0`) | `bundle_writer.apply_node_pseudo` → `_style.redact_pseudo` | §C9-R-P8 / P8-GEOM |
| `theme` | Regime-3a theme/preference (`prefers-color-scheme`) delta | `bundle_writer.apply_node_theme` → `_style.redact_theme` | §C9-R-P9 |
| `pseudo_state` | Regime-3b interactive `:hover`/`:focus`/`:active` delta | `bundle_writer.apply_node_pseudo_state` → `_style.redact_pseudo_state` | §C9-R-P10 |
| `responsive` | Regime-3c multi-viewport reflow delta | `bundle_writer.apply_node_responsive` → `_style.redact_responsive` | §C9-R-P11 |
| `keyframes` | Regime-4a CSS `@keyframes` map | `bundle_writer.apply_node_keyframes` → `_style.redact_keyframes` | §C9-R-P12 |
| `reduced_motion` | `prefers-reduced-motion` computed-style delta | `bundle_writer.apply_node_reduced_motion` → `_style.redact_reduced_motion` | §C9-R-P13 |
| `form_state` | Form `:checked`/`:disabled` computed-style delta | `bundle_writer.apply_node_form_state` → `_style.redact_form_state` | §C9-R-P14 |
| `container` | Fixed-width `@container` restyle delta | `bundle_writer.apply_node_container` → `_style.redact_container` | §C9-R-P15 |

**Leak-site note:** the delta maps (`theme`/`pseudo_state`/`responsive`/`reduced_motion`/`form_state`/`container`) are NOT key-stripped by `redact_node` — their redactor is a passthrough, so the firewall `_CSS_URL_REF` regex (`content_firewall.py`) is the sole backstop against a `url(https://…)` asset ref in a delta value. Covered by `test_audit_canary_unredacted_external_url_in_style_trips`.

**Pseudo `bbox` IP note (§C9-R-P8-GEOM):** a pseudo's `bbox` is content-free geometry (floats), passed through verbatim by `redact_pseudo`. Even for a text-bearing `::before`/`::after`, the width/height is the *same lossy text-geometry the bundle already ships for every real text node* — and real text nodes carry `bbox` **plus `text_len`**, whereas a pseudo ships `bbox` **only** (no `text_len`). A text-pseudo's geometry is therefore strictly *less* revealing than the already-accepted real-text-node tolerance, not a new vector.

## Bundle-level outputs (per route)

| File | Feature | Producer | Provenance |
|---|---|---|---|
| `tokens.json` | Design-token palette | `web_tokens` | §C9 |
| `substrate.json` | Substrate summary | `bundle_writer` | §C9-R-P2 |
| `states.json` | Driven interaction states: components + transitions (ARIA-affordance triggers) | `web_states` (`_states.build_component`/transition) | §C9-R-P1 / P4 / P5 |

## Cross-route (site) outputs (`site_capture --merge --dedup`)

| File | Feature | Producer | Provenance |
|---|---|---|---|
| `site.json` | Multi-route manifest (positional ids only) | `site_capture` | §C9-R-G3a |
| `design_system.json` | Cross-route token merge (clustered palette) | `site_merge` → `_merge.build_design_system` | §C9-R-G3b |
| `chrome_dedup.json` | Shared-chrome dedup (opt-in post-processor) | `site_chrome` | §C9-R-G3-wire |

**Deferred (not shipped):** G3c recurring-component synthesis (×2), G3d exact-lossless chrome dedup, G2 virtualization sweep-merge (engine LANDED but DORMANT behind opt-in `--sweep`, default off; ship-test **DEFER** — the de-risked gain did not reproduce on the produced artifact: demo `new_shapes=17 < 25`, `repro_delta=0.452 > 0.20`; engine proven faithful, gain regime-fragile; see §C9-R-G2 ship-test), G4 hover/non-ARIA trigger detection. See the capture-gaps plan.

## Validating a real capture (manual)

Unit tests cover the pure funcs + `assemble`/`audit` composition deterministically.
To validate the LIVE end-to-end path on real artifact bytes (per the
`validate-real-artifact-not-keys-proxy` lesson), run the manual harness against a
debug Chrome with a fresh tab:

```
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222   # then open exactly ONE tab
python3 scripts/livesmoke_web_capture.py
```

Exit 0 = real artifact captured (skeleton + tokens + G3b merge + dedup + states) with real field values and 0 firewall violations on the produced bundle AND the states delta tree. Prereq: **exactly one** clean `:9222` page target — with >1 tab the capture's target-resolution can attach to a stale tab and hang. Runtime ~3–4 min. It is a manual harness, NOT a suite test: a live capture against one shared mutable Chrome tab is too slow/stateful for CI (and always-skips headless).
