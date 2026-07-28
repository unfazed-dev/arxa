# Regime-1 CSS property coverage (cut 1) — design spec

**Status:** approved (2026-05-31). Next: implementation plan via writing-plans → subagent-driven execution.

**Roadmap context:** First of the "later acquisition gaps" (the category after the §C9 ladder + P4 component + P5 transition). Source: `docs/research/css-capture-completeness.md`, which measures the tool's per-node whitelist + tokens against modern-site CSS and tags each gap by effort "Regime." **Regime 1** = a property whose resolved value is faithful and can be captured by adding it to the computed-style read (cheap). This spec is **cut 1** — it proves the capture→redact→audit pipeline on a representative, high-impact subset; remaining Regime-1 properties are trivial follow-on through the proven pipeline.

---

## Goal

Capture the high-impact visual CSS the tool currently DROPS (`filter`, `backdrop-filter`, `box-shadow` per node, full border, `border-radius` corners, `transform-origin`, `clip-path`, `mix-blend-mode`, `background-image`) as a content-free per-node `style` field of resolved values — so the bundle carries the design's visual mechanism, not a flattened approximation.

## Principle alignment

- **Content-free invariant.** The `style` field carries resolved CSS values — numbers, enums, color strings, gradient/shape function strings — the same content-free class as the already-shipped `_node_colors` `rgb()/rgba()` and tokens' `box-shadow` strings (empirically re-confirmed, see Firewall below). The ONE content vector is `url(...)` pointing at an external/`data:` asset; it is redacted at packaging.
- **Content-blind capture (principle #2).** `web_skeleton` is a capture verb — it records the RAW resolved value (including `url()`) and NEVER runs the firewall. Redaction is a packaging-time concern (`bundle_writer`/`_style`), mirroring how `_node_colors` is captured raw and mapped at packaging.
- **Honest ceiling.** An external background image becomes a content-free `url("<asset>")` marker (a slot-like fill point), never the real URL or bytes. Raster bytes are out of scope (Regime 4). Resolved values are faithful but unparsed — gradient/shadow structured decomposition is reproduction-side, explicitly deferred.

## Firewall (empirically de-risked, before any code)

`cf.audit_bundle` was run in-sandbox on a skeleton carrying each candidate value:

| value | audit |
|-------|-------|
| `blur(10px)`, `linear-gradient(…)`, `polygon(…)`, multi/inset `box-shadow` (`rgba…`), `transform-origin` px, enums (`dashed`, `multiply`) | **CLEAN** |
| `url(#blur)`, `url("#clip-shape")` — same-doc fragment refs | **CLEAN** |
| `url("https://cdn…/photo.png")` | **VIOLATION** `content-url` |
| `url("data:image/…")` | **VIOLATION** `data-uri` |

**Conclusion — the redaction discriminator is exact and minimal:** redact only a `url(...)` token whose target is external (`http`, `https`, protocol-relative `//`) or `data:`; **keep** `url(#fragment)` (same-doc) untouched. Everything else is content-free as captured. Internal `#ref`s (filter/clip-path mechanism) already pass — no normalization is required for firewall passage (we may strip surrounding quotes for cleanliness, but must NOT strip the `url()` itself — the P5 over-normalization lesson: do not destroy mechanism while removing content).

## Architecture

```
web_skeleton (capture, content-blind)
  └─ extend _WHITELIST with cut-1 props
  └─ emit sk["_node_style"] = { "<id>": { "<prop>": "<resolved value, RAW incl url()>" } }
        (mirrors sk["_node_colors"]; no redaction here)

_style.py (pure core)
  └─ redact_style_value(value) -> value with external/data: url(...) tokens replaced
       by url("<asset>"); same-doc #fragment url() and all other tokens preserved
  └─ redact_node_styles(node_style_map) -> {id: {prop: redacted_value}}

bundle_writer.assemble / write_bundle
  └─ pop skeleton["_node_style"] pre-disk (exactly like _node_colors)
  └─ node["style"] = redact_node_styles(...)[node_id]   (attach per node)
  └─ firewall audits the written bundle -> clean
```

Schema: a per-node additive `style` field (the `consent`/`component`/`transition`/`_node_colors` additive precedent). No new top-level artifact, no schema-version bump.

## Data shapes

- **Sidecar (capture output, raw):** `sk["_node_style"] = {"<node_id>": {"filter": "blur(10px)", "background-image": "url(\"https://…\")", "border-top-style": "solid", …}}`. Sparse — a property is emitted ONLY when it has visual effect:
  - `none`/`normal`/empty/`auto` resolved values are dropped (`filter:none`, `clip-path:none`, `box-shadow:none`, `mix-blend-mode:normal`, `background-image:none`, `border-*-style:none`).
  - zero-valued metrics dropped (`border-*-width:0px`, `border-*-radius:0px`).
  - `transform-origin` is emitted ONLY when `transform` is not `none` (it always resolves to a px pivot otherwise — irrelevant default noise on every node).
  - A node with no surviving property → no `_node_style` entry at all (exactly as `_node_colors` only carries set colors).
- **`redact_style_value(value: str) -> str`:** pure; replaces each external/`data:` `url(...)` token with `url("<asset>")`, leaves `url(#…)` and the rest of the string intact. Idempotent. Returns the input unchanged when no `url()` is present.
- **Node field (on disk):** `node["style"] = {"<prop>": "<redacted resolved value>"}`. Absent when the node had no captured style.

## Cut-1 property set

> **As-built (2026-05-31):** `-webkit-backdrop-filter` was DROPPED — invalid for Chrome's `DOMSnapshot.captureSnapshot` `computedStyles` (Blink exposes only the unprefixed `backdrop-filter`). See capture-gaps §C9-R-P6.

`filter`, `backdrop-filter`, ~~`-webkit-backdrop-filter`~~ *(DROPPED as-built — see note above)*, `background-image` (the **external-url exerciser**), `clip-path` (the **internal-#ref exerciser**), `box-shadow`, `border-top-style`, `border-right-style`, `border-bottom-style`, `border-left-style`, `border-right-width`, `border-bottom-width`, `border-left-width`, `border-right-color`, `border-bottom-color`, `border-left-color`, `border-top-left-radius`, `border-top-right-radius`, `border-bottom-right-radius`, `border-bottom-left-radius`, `transform-origin`, `mix-blend-mode`.

(`border-top-width`/`border-top-color` are already read by the tokens walk but not per-node; cut-1 captures all four sides per node. `background-color`/`color`/`border-top-color` per-node stay in the existing `_node_colors` sidecar — `style` does NOT duplicate them.)

**Deferred (trivial follow-on):** gradient/shadow structured parsers; `background-{size,position,repeat,clip,origin,attachment,blend-mode}`; `outline-*`; `text-shadow`; `overflow-{x,y}`; `aspect-ratio`; `object-{fit,position}`; typography suite (`text-transform`/`text-decoration`/`font-variant`/`writing-mode`/`direction`/…); transform-3d (`perspective`/`transform-style`/individual `rotate`/`scale`/`translate`); interactive/responsive states (Regime 3); pseudo-elements (Regime 2).

## Components / files

- **`scripts/_style.py`** (new, pure core): `redact_style_value(value)`, `redact_node_styles(node_style_map)`, plus the private `url()` tokenizer/classifier. No browser, no I/O. Unit-tested.
- **`scripts/web_skeleton.py`** (modify): extend `_WHITELIST` with the cut-1 props (respecting the parallel-index contract — `layout.styles[i]` aligns to `_WHITELIST`); build and attach `sk["_node_style"]` from the read styles (drop default/none/empty); a `style` builder analogous to the `_node_colors` block.
- **`scripts/bundle_writer.py`** (modify): pop `skeleton["_node_style"]` pre-disk; attach `node["style"] = redact_node_styles(...)` per node, mirroring the `_node_colors` handling.
- **`scripts/test_style.py`** (new): pure-core unit tests for the redaction discriminator (external http/https/`//`/`data:` redacted; same-doc `#frag` kept; layered `gradient + url(...)` redacts only the url; no-url passthrough; idempotence).
- **`scripts/test_web_skeleton.py`** (modify): a test pinning the `_WHITELIST` ↔ `styles[i]` parallel-index alignment after extension (mechanical-risk guard).
- **`scripts/test_content_firewall.py`** (modify): a `style`-carrying skeleton.json (incl. an external-url `background-image` already redacted to `url("<asset>")`, plus an internal-`#ref` `clip-path` and a gradient) audits clean; AND a canary that an UN-redacted external url in `style` DOES trip (proves the redaction is load-bearing, not decorative).
- **`scripts/test_bundle_writer.py`** (modify): round-trip — a skeleton with `_node_style` containing an external url produces a bundle whose node `style` is redacted and whose audit passes.
- **`fixtures/css_style/run_css_style.py`** (new): host gate — serve a page with a node using `filter`, `backdrop-filter`, `clip-path:url(#c)` + an inline `<svg><clipPath id=c>`, a `linear-gradient` background, a full dashed border with per-corner radius, AND an external `background-image:url(http://127.0.0.1:port/x.png)` (served by the same local server, so offline). Drive `web_skeleton`; assert the node `style` carries the resolved filter/clip/gradient/border, the internal `#ref` survived, and the external url was redacted to `url("<asset>")`.

## Verification strategy

- **Pure core** (`_style.py`) → exhaustive unit tests (the redaction discriminator is the load-bearing logic).
- **Parallel-index pin** → a `test_web_skeleton` test that the extended `_WHITELIST` stays aligned with the `styles[i]` rows.
- **Firewall** → real `cf.audit_bundle`: a redacted `style` audits clean; an un-redacted external url trips (canary).
- **Round-trip** → `bundle_writer` test that `_node_style` (raw, with external url) → on-disk `style` (redacted) → audit clean.
- **End-to-end** → offline host gate; everything served from one local server (the "external" url is `http://127.0.0.1:port/...`, redacted by the http discriminator). Run on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox).

## Mechanical risk — the parallel-index contract

`web_skeleton._WHITELIST` defines the order of `DOMSnapshot.captureSnapshot` `computedStyles`; `layout.styles[i]` rows are PARALLEL to it. Extending the whitelist must keep every existing index stable (append, do not reorder) and the per-node style dict must read by the correct index/name. A unit test pins the alignment.

## Commits

Single-line messages, no trailers. Stage files explicitly by path. One commit per task. Local on master — do NOT push.
