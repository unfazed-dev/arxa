# Regime-1 CSS property coverage (cut 2) — design spec

**Status:** landed (2026-05-31) — see capture-gaps §C9-R-P7.

**Roadmap context:** The deferred follow-on from cut 1 (`docs/plans/regime1-css-property-coverage-design.md`, landed §C9-R-P6). Cut 1 proved the capture→redact→audit pipeline on a high-impact visual subset; cut 2 completes the Regime-1 acquisition set (everything obtainable by adding a property name to the computed-style read) through that same proven pipeline. Reproduction-side gradient/shadow **structured parsers** stay out of scope (they decompose already-captured strings — a reproduction concern, not acquisition).

---

## Goal

Capture the remaining Regime-1 visual CSS the tool still drops — background longhands, outline, text-shadow, overflow, aspect-ratio, object-fit/position, the typography suite, and transform-3d — into the existing content-free per-node `style` field, so the bundle carries the full Regime-1 visual mechanism.

## Principle alignment

- **Content-free invariant.** All 27 cut-2 props resolve to numbers, enums, color strings, or shape/shadow function strings — the same content-free class already shipped in cut 1. **No new content vector:** none of these props carry a `url()` (background longhands describe how the already-captured `background-image` is painted; the rest are enums/metrics/colors). Therefore `_style.py` and `bundle_writer.py` are UNCHANGED — the cut-1 `url()` redactor and prop-agnostic attach already cover everything.
- **Content-blind capture (principle #2).** `web_skeleton` reads RAW resolved values into the `_node_style` sidecar (no firewall at capture); redaction stays a packaging concern. Unchanged from cut 1.
- **Honest ceiling.** Resolved values are faithful but UNPARSED — `text-shadow`/gradient structured decomposition stays deferred (reproduction-side). A prop Chrome rejects from `DOMSnapshot.captureSnapshot` is dropped and documented, never force-fit (the cut-1 `-webkit-backdrop-filter` precedent).

## Cut-2 property set (27 props)

Appended to `WANT_STYLES` (append-only — every existing index stays stable) and added to `STYLE_PROPS`:

- **Backgrounds (7):** `background-size`, `background-position`, `background-repeat`, `background-clip`, `background-origin`, `background-attachment`, `background-blend-mode`
- **Outline (4):** `outline-style`, `outline-width`, `outline-color`, `outline-offset`
- **Text-shadow (1):** `text-shadow`
- **Box/layout (3):** `overflow-x`, `overflow-y`, `aspect-ratio`
- **Object (2):** `object-fit`, `object-position`
- **Typography (5):** `text-transform`, `text-decoration-line`, `font-variant`, `writing-mode`, `direction`
- **Transform-3d (5):** `perspective`, `transform-style`, `rotate`, `scale`, `translate`

`background-image`, `background-color`, `color`, and the per-side border props already ship (cut 1 / `_node_colors`); cut 2 does NOT duplicate them. `text-decoration-line` (not the `text-decoration` shorthand) is used — Chrome resolves the shorthand to a multi-token string (`none solid rgb(...)`) that defeats noop-drop; the `-line` longhand resolves to `none` on the default case.

## Sparse-drop — per-prop default map + gating

`_collect_style` keeps cut-1's drop and gains a third layer + one new gated group. A property is emitted ONLY when it carries non-default visual effect (the cut-1 sparse-sidecar principle — a node with no surviving prop gets no `_node_style` entry, exactly like `_node_colors`).

1. **Universal noop** (`None`/`""`/`none`/`normal`/`auto`) — unchanged. Covers (confirmed by probe 0b): `background-size` (auto), `background-blend-mode` (normal), `text-shadow` (none), `aspect-ratio` (auto), `text-transform` (none), `text-decoration-line` (none), `font-variant` (normal), `perspective` (none), `rotate`/`scale`/`translate` (none), `outline-style` (none).
2. **Zero-metric** — the existing `-width`/`-radius` zero-px drop, unchanged. (NOTE — probe correction: Chrome's default `outline-width` is `1.5px`, **not** `0`, so the zero rule does NOT suppress a default outline; the outline group is handled by gating instead, below.)
3. **Per-prop default map** — `_STYLE_DEFAULTS = {prop: {default-value-strings}}`; drop a prop when its resolved value (lower-cased) is in its default set. Populated **empirically from probe 0b** (12 props whose Chrome resolved default is NOT in the universal noop set): `background-position` `{"0% 0%"}`, `background-repeat` `{"repeat"}`, `background-clip` `{"border-box"}`, `background-origin` `{"padding-box"}`, `background-attachment` `{"scroll"}`, `overflow-x`/`overflow-y` `{"visible"}`, `object-fit` `{"fill"}`, `object-position` `{"50% 50%"}`, `writing-mode` `{"horizontal-tb"}`, `direction` `{"ltr"}`, `transform-style` `{"flat"}`.

**Gated groups (cross-prop):** mirror the existing `transform-origin`-only-when-`transform` gate.
- **Outline group:** `outline-width`, `outline-color`, `outline-offset` are emitted ONLY when `outline-style` is set (non-`none`). Required because Chrome resolves them to non-suppressible defaults on EVERY node (`outline-width:1.5px`, `outline-color:rgb(0,0,0)`, `outline-offset:0px`) — gating, not value-drop, is the correct guard.
- Backgrounds are NOT gated on `background-image`: the default map suppresses the all-default case, and `background-clip:text` is meaningful without an image — keep them value-driven, no cross-prop coupling.

## Architecture (delta from cut 1)

```
web_skeleton (capture, content-blind)        ← ONLY file with logic changes
  └─ WANT_STYLES   += 27 props (append-only; parallel-index contract preserved)
  └─ STYLE_PROPS   += new props
  └─ _collect_style: + _STYLE_DEFAULTS map + outline-group gate (width/color/offset on outline-style)

_style.py            ← UNCHANGED (no new url() vector)
bundle_writer.py     ← UNCHANGED (prop-agnostic apply_node_style)
```

Schema: still the additive per-node `style` field. No new artifact, no schema-version bump.

## Components / files

- **`scripts/web_skeleton.py`** (modify): append the 27 props to `WANT_STYLES` (after the cut-1 block, keeping order) and to `STYLE_PROPS`; add `_STYLE_DEFAULTS`; extend `_collect_style` with the default-map layer and the outline-group gate (`outline-width`/`outline-color`/`outline-offset` emitted only when `outline-style` is set).
- **`scripts/_style.py`** — NO CHANGE. State this explicitly so a reviewer does not expect one.
- **`scripts/bundle_writer.py`** — NO CHANGE.
- **`scripts/test_web_skeleton.py`** (modify): tests for default-map drop (a node carrying only Chrome-default values yields no `style`), per-prop emission (non-default value survives), outline-group gating (`outline-width`/`outline-color`/`outline-offset` dropped when `outline-style:none`, kept when `outline-style` set), extended parallel-index pin (new `WANT_STYLES` indices align to `styles[i]`), and the `STYLE_PROPS ⊆ WANT_STYLES` guard stays green.
- **`scripts/test_content_firewall.py`** (modify): a `style`-carrying skeleton with cut-2 values (`text-shadow`, `outline`, background longhands, `object-position`) audits clean — confirms no new prop introduces a content signature. (No new canary needed — no new url() vector.)
- **`scripts/test_bundle_writer.py`** (modify): round-trip — a `_node_style` carrying cut-2 props produces a bundle whose node `style` survives `cf.redact_node` and audits clean.
- **`fixtures/css_style/run_css_style.py`** (modify): extend the offline host-gate page with nodes exercising the new props — an `<img>` with `object-fit`/`object-position`, an `outline` + `outline-offset`, a `text-shadow`, background `size`/`position`/`repeat`, an `overflow:hidden` clip, an `aspect-ratio` box, a `writing-mode`/`direction` block, a `transform-style:preserve-3d`/`perspective` parent. Assert each populates its `style`, the all-default nodes stay absent from `_node_style`, and the bundle audits clean.
- **Real-site validation (new, one-off, NOT in the committed suite):** a content-free host script (`fixtures/css_style/validate_realsite.py`) takes `--url`, drives the full pipeline on host CDP, and prints ONLY: which cut-2 props populated (prop NAMES + occurrence COUNTS), the bundle audit verdict, and node counts. **No page content, no resolved values, no URLs are persisted or printed** — IP firewall + content-free invariant. Run once against a chosen public page; record the content-free summary in capture-gaps §C9-R-P7.

## Verification strategy

- **Empirical de-risk — DONE during planning (2026-05-31, host CDP):**
  - **Probe 0a — prop validity:** ALL 27 props ACCEPTED by `DOMSnapshot.captureSnapshot` (no `-webkit`-style rejects this time). Full 27-prop set ships.
  - **Probe 0b — resolved defaults:** Chrome's resolved defaults recorded on a bare `<div>`/`<img>`; `_STYLE_DEFAULTS` (12 entries above) is populated verbatim from this output. Surfaced the `outline-width:1.5px` correction (gating, not zero-drop).
- **Pure logic** → `test_web_skeleton` unit tests (default-map, gating, zero-drop).
- **Parallel-index pin** → extended `WANT_STYLES`↔`styles[i]` alignment test + `STYLE_PROPS ⊆ WANT_STYLES` guard.
- **Firewall** → `cf.audit_bundle` clean on a cut-2-valued skeleton.
- **Round-trip** → `bundle_writer` test.
- **Synthetic host gate** → extended `fixtures/css_style/run_css_style.py` (deterministic, offline; host Bash, `dangerouslyDisableSandbox=true` — CDP unreachable from the ctx sandbox).
- **Real-site validation** → one-off host run (above), content-free, recorded in §C9-R-P7.

## Mechanical risk — the parallel-index contract

`web_skeleton.WANT_STYLES` defines the column order of `DOMSnapshot.captureSnapshot` `computedStyles`; `layout.styles[i]` rows are parallel. The 27 props are APPENDED after the cut-1 block — existing indices stay stable. The parallel-index pin test is extended to cover the new tail. A property name read by the wrong index silently captures the wrong value; the pin guards it.

## Honest ceilings (documented, not force-handled)

- A prop Chrome rejects from `captureSnapshot` is dropped (probe 0a), not worked around.
- Resolved values are faithful but UNPARSED — gradient/shadow/`text-shadow` structured decomposition stays deferred (reproduction-side).
- Per-prop defaults are Chrome's resolved strings; a value that is visually default but textually differs across engines is an honest single-engine ceiling (the tool captures the Chromium resolved value).
- **`outline-style: auto` over-drops** — `outline-style` is judged by the universal noop set (which contains `auto`) and gates the outline group, so an explicitly authored `outline-style: auto` (the visible UA focus-ring style) is treated as unset and the whole group is dropped. (The analogous `overflow-x/y: auto` and `object-fit: none` divergences are NOT lost: those props carry `_STYLE_DEFAULTS` entries, and the map is authoritative over the noop set — a review-found fix — so their meaningful noop-looking values survive. `outline-style` is *gated*, not mapped, so it remains the one over-drop.) Accepted as a narrow ceiling, not force-handled: `auto` is the focus-ring renderer and rarely surfaces in a static `captureSnapshot` (no focus simulation); special-casing it would add a wart to the load-bearing `_collect_style`. Authored `none`/`solid`/`dashed`/`dotted`/etc. outlines are captured faithfully.

## Commits

Single-line messages, no trailers. Stage files explicitly by path. One commit per task. Local on master — do NOT push.
