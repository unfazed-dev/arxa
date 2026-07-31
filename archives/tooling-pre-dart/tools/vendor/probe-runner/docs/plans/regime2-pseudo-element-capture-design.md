# Regime-2 pseudo-element capture — design spec

**Status:** approved (2026-05-31). Next: implementation plan via writing-plans → subagent-driven execution.

**Roadmap context:** The capture-regime ladder (`docs/research/css-capture-completeness.md`) ranks gaps by acquisition cost. Regime 1 (one-pass add to the computed-style whitelist) is COMPLETE (cut 1 §C9-R-P6, cut 2 §C9-R-P7). **Regime 2** is the pseudo-element pass. The research doc carried the premise "DOMSnapshot does NOT enumerate pseudo-elements, so this needs a separate `getComputedStyle(el, '::before')` JS pass per node per pseudo." **An orientation probe (2026-05-31, host CDP) refuted that premise:** `DOMSnapshot.captureSnapshot` DOES enumerate `::before`/`::after`/`::marker` as nodes carrying `pseudoType`, an own `nodeName` (`::before`/`::after`/`::marker`), a populated parallel `layout.styles` row, and a `parentIndex` pointing at the originating element. **Regime 2 therefore collapses to a Regime-1-style extension** — no separate pass, no DOM stamping, no join problem. Reproduction-side gradient/shadow/`content` structured parsers stay out of scope (decompose already-captured strings — a reproduction concern).

---

## Goal

Capture `::before`/`::after`/`::marker` resolved box-style + a content-free `content` value as an additive per-node `pseudo` field on the **originating element's** skeleton node, so the bundle carries pseudo-element visual mechanism (generated-content boxes, decorative glyphs, list markers) the tool currently drops.

## Empirical de-risk (DONE during brainstorming, host CDP, self-authored page)

- **Probe — pseudo enumeration:** `nodes` contains `pseudoType` (sparse RareStringData). On a synthetic page the distinct values were `{before, after, marker}`; each pseudo node had `layout_row=True` (a full parallel `styles` row: `content`/`color`/`display`/`width`/`height`/`background-image` all resolved) and `parentIndex` → the originating `DIV`/`LI`.
- **Reachability ceiling (empirical, NOT a choice):** `::placeholder` is reachable via in-page `getComputedStyle(input, '::placeholder')` but is **NOT** enumerated by `captureSnapshot` (absent from `pseudoType`). `::selection`/`::first-line`/`::first-letter`/`::backdrop` likewise do not surface. Out of scope, documented.
- **`content` resolution forms (drives the redaction discriminator):**
  - quoted string `"Read more"`; glyph `"→"`; `attr(data-x)` **resolves to the literal** `"LABEL"`; alt syntax `"icon" / "alt label"` — all authored content.
  - `url("http://127.0.0.1:1/x.png")` — the cut-1 url() vector.
  - `counter(foo)` stays **symbolic** (NOT resolved to a number) — mechanism.
  - `normal` (default `::marker`/`::placeholder`), `none` — noop.

## Principle alignment

- **Content-free invariant.** Pseudo box-style values are the same content-free class already shipped (numbers, enums, `rgb()` colors, shape/shadow strings). The ONE new content vector is `content` (authored text). It is redacted at packaging: string literals → `"<text>"`; `url()` → `url("<asset>")` (cut-1 redactor); `counter()`/quote keywords kept (mechanism).
- **Content-blind capture (principle #2).** `web_skeleton` records the RAW resolved `content` (incl. literal text and `url()`) into the `_node_pseudo` sidecar; redaction stays a packaging concern (`bundle_writer`/`_style`), exactly as cut-1 captured `url()` raw and redacted at packaging.
- **Honest ceiling.** Only the captureSnapshot-enumerated pseudos (`::before`/`::after`/`::marker`) are captured; the rest are documented gaps, never force-fit. Resolved values are faithful but UNPARSED.

## Pseudo set

`::before`, `::after`, `::marker` — the full set `captureSnapshot` enumerates with layout+style rows. Keyed in the bundle by the selector form (`"::before"`, `"::after"`, `"::marker"`), matching the node's own `nodeName`.

## Architecture (delta from cut 2)

```
web_skeleton (capture, content-blind)        ← ONLY capture-side file with logic changes
  WANT_STYLES   += ["content"]               (append-only; parallel-index contract preserved)
  STYLE_PROPS    UNCHANGED                    (content is NOT a generic per-node style prop;
                                               real elements resolve content→normal anyway)
  parse_snapshot: each record gains  r["pseudo"] = "before"|"after"|"marker"|None
                  (read from nodes["pseudoType"] sparse {index:[],value:[]} map)
  _collect_pseudo(row, parent_color):         new helper — see "Pseudo style collection"
  to_skeleton:    pseudo records are NOT classified/emitted as standalone nodes;
                  they are HARVESTED into  sk["_node_pseudo"] = {node_id: {sel: {style}}}
                  keyed by the originating element's skeleton id via a DIRECT
                  dom_to_id lookup on the pseudo's parentIndex (drop on miss — no walk-up).

_style.py (pure core)
  redact_content_value(content) -> tokenize; per-token: url()→redact_style_value,
                                    quoted-string→"<text>", counter()/*-quote keyword→keep.
  redact_node_pseudo(pseudo_map) -> per pseudo: content key→redact_content_value,
                                     every other value→redact_style_value (box url() vector).

bundle_writer
  pop skeleton["_node_pseudo"] pre-disk (exactly like _node_colors);
  node["pseudo"] = redact_node_pseudo(...)[node_id]   (attach per node);
  firewall audits the written bundle → clean.
```

Schema: an additive per-node `pseudo` field (the `style`/`consent`/`component`/`transition`/`_node_colors` additive precedent). No new artifact, no schema-version bump.

## Data shapes

- **Sidecar (capture output, raw):**
  `sk["_node_pseudo"] = {"<node_id>": {"::before": {"color": "rgb(255, 0, 0)", "text-shadow": "rgb(0,0,0) 1px 1px 2px", "content": "\"Read more\""}, "::after": {"background-image": "url(\"https://…\")"}, "::marker": {"color": "rgb(255,0,0)"}}}`.
  Sparse — a pseudo selector appears ONLY when `_collect_pseudo` returns a non-empty dict; a node with no rendering pseudo gets no `_node_pseudo` entry. **No geometry** (width/height/bbox of the pseudo box) — only visual-style props + fg/bg/border-top-color + `content` (see Honest ceilings).
- **Node field (on disk):**
  `node["pseudo"] = {"::before": {"color": "rgb(255, 0, 0)", "content": "\"<text>\""}}`. Absent when the node had no captured pseudo.

## Pseudo style collection — `_collect_pseudo(row, parent_color)`

`row` is the pseudo's parallel style dict (keys = `WANT_STYLES`, values = resolved strings). `parent_color` is the originating element's resolved `color`.

1. `out = _collect_style(row)` — reuses the cut-1+cut-2 box collector verbatim: `filter`, `box-shadow`, border `style`/`width`/`radius`, the 3 non-top border colors (cut-1 captures right/bottom/left-color), `transform`/`transform-origin`, background longhands, `overflow`, `object-*`, the cut-2 typography/3d set, with all the noop/default/zero/outline-gate drops already proven.
2. **Add the three color props `_collect_style` excludes** (they belong to the `_node_colors` model), captured inline as resolved `rgb()` (content-free, audits clean — no palette/token_ref plumbing for pseudos):
   - `background-color`: emit unless transparent (`{"transparent", "rgba(0, 0, 0, 0)"}`).
   - `border-top-color`: emit only when `border-top-style` is set (non-noop) — gated like the outline group; completes all four border colors (top here + right/bottom/left from `_collect_style`).
   - `color`: emit **only when `row["color"] != parent_color`** (resolved-string inequality). This is the discriminator that keeps the sidecar sparse: a default `::marker` inherits its list's text color (`color == parent_color`) → dropped; `li::marker { color: red }` differs → captured. (Color inherits, so it has no fixed default — parent-diff is the correct sparseness rule. Other inherited props — `font-variant`/`writing-mode`/`direction`/`text-transform` — already default-drop in `_collect_style`; `font-size`/`font-family` are not in `STYLE_PROPS`, so a pseudo never duplicates them.)
3. **Add `content`** (raw, redacted at packaging) when `row["content"]` is present and its lower-cased strip is not in `{"none", "normal", ""}`.
4. Return `out` (possibly `{}` → caller emits no sidecar entry for this pseudo).

## content firewall — `redact_content_value(content)`

`content` is a token list, not a single value: `"a" counter(x) url(...) open-quote "b" / "alt"`. A naive regex sub corrupts state — `url("http://x")` *contains* a quoted string, and the post-url marker `url("<asset>")` *also* contains one. Therefore **tokenize and classify each token**, never re-scan a rebuilt token.

Token alternation, scanned left-to-right (case-insensitive, dotall):
- `url(\s*(['"]?).*?\2\s*\)` → `redact_style_value(token)` (external/data → `url("<asset>")`; same-doc `url(#frag)` kept).
- `"(?:[^"\\]|\\.)*"` or `'(?:[^'\\]|\\.)*'` (quoted string, incl. attr-resolved literals) → replace with `"<text>"`.
- `counters?\([^)]*\)` (counter/counters), the `/` alt separator, and bareword keywords (`open-quote`, `close-quote`, `no-open-quote`, `no-close-quote`, etc.) → keep verbatim (mechanism).
Rejoin the mapped tokens with single spaces.

Examples: `"Read more"`→`"<text>"`; `counter(foo)`→`counter(foo)`; `url("https://x/y.png")`→`url("<asset>")`; `url("#frag")`→`url("#frag")`; `"icon" / "alt"`→`"<text>" / "<text>"`; `url("http://x") " label"`→`url("<asset>") "<text>"`; `"a" counter(x) "b"`→`"<text>" counter(x) "<text>"`.

**Firewall backstop scope (honest):** `cf.audit_bundle` catches the `url()`/data:/binary-magic vectors (so an un-redacted EXTERNAL url in `content` trips — a valid canary, like cut-1) AND authored prose ≥25 ASCII chars (`_PROSE`) / ≥4 non-ASCII chars (`_NONASCII_PROSE`). So a long un-redacted `content` string would also trip. The genuinely **un-backstopped** case is a SHORT (<25-char ASCII) authored string (e.g. `"Menu"`, a glyph) — there the string-literal → `"<text>"` redaction is the sole protection. It is verified directly by `redact_content_value` unit tests AND a `bundle_writer` round-trip assertion that a raw authored content string does NOT appear on disk (redacted to `"<text>"`).

## Components / files

- **`scripts/web_skeleton.py`** (modify): append `content` to `WANT_STYLES` (after the cut-2 block, append-only); add `r["pseudo"]` to each `parse_snapshot` record (from `nodes["pseudoType"]`); add `_collect_pseudo(row, parent_color)`; in `to_skeleton`, route pseudo records into `sk["_node_pseudo"]` via a direct `dom_to_id` lookup on the pseudo's `parentIndex` (drop on miss), instead of classifying/emitting them as nodes.
- **`scripts/_style.py`** (modify): add `redact_content_value(content)` (tokenizer) and `redact_node_pseudo(pseudo_map)`. `redact_style_value`/`redact_node_styles` UNCHANGED.
- **`scripts/bundle_writer.py`** (modify): pop `skeleton["_node_pseudo"]` pre-disk; attach `node["pseudo"] = redact_node_pseudo(...)[node_id]` per node, mirroring `_node_colors`/`_node_style` handling.
- **`scripts/test_style.py`** (modify): `redact_content_value` discriminator tests (string→`<text>`; counter/quote-keyword kept; external/data url→`<asset>`; `#frag` kept; mixed url+string; alt `"x" / "y"`; idempotence — `"<text>"` and `url("<asset>")` re-redact to themselves).
- **`scripts/test_web_skeleton.py`** (modify): pseudo `parse_snapshot` (a `pseudoType` node yields `r["pseudo"]`); `to_skeleton` join (a `::before` row attaches to the CORRECT parent node id; a pseudo whose parent is unemitted is dropped, NOT reattached); `_collect_pseudo` color parent-diff (default marker dropped, custom-color marker kept); extended parallel-index pin (`content` aligns to `styles[i]`); `STYLE_PROPS ⊆ WANT_STYLES` guard stays green (and `content ∈ WANT_STYLES`, `content ∉ STYLE_PROPS`).
- **`scripts/test_content_firewall.py`** (modify): a `pseudo`-carrying skeleton (redacted `content` `"<text>"`, an internal-`#ref` and a gradient box prop) audits clean; canary — an un-redacted EXTERNAL `url()` inside a pseudo `content`/`background-image` DOES trip.
- **`scripts/test_bundle_writer.py`** (modify): round-trip — a `_node_pseudo` carrying a raw external url + a raw authored string produces a bundle whose `node["pseudo"]` is redacted (`url("<asset>")`, `"<text>"`), the raw string is ABSENT, and the audit passes.
- **`fixtures/css_style/run_css_style.py`** (modify) — extend the existing **local-server** offline host gate (NOT a `data:` URL / `navigate` — the orientation probe proved `navigate` can silently capture a live tab) with nodes exercising: a `::before` with a string `content` + box size/color; an `::after` with an external `background-image:url(http://127.0.0.1:port/x.png)` served by the same local server; a **custom-styled** `li::marker { color: … }` (a default bullet correctly yields `_collect_pseudo → {}` and is asserted ABSENT; assert on the custom one). Assert each populates `node["pseudo"]`, the external url redacts to `url("<asset>")`, the string `content` redacts to `"<text>"`, and the bundle audits clean.
- **Real-site validation (one-off, NOT in the committed suite):** extend/clone `fixtures/css_style/validate_realsite.py` — drive the full pipeline on host CDP against a chosen public page and print ONLY `{pseudo-selector: occurrence-count}` and the audit verdict. **No `content` value, no resolved string, no URL is printed or persisted.** Record the content-free summary in capture-gaps §C9-R-P8.

## Verification strategy

- **Pure logic** → `test_style` (`redact_content_value` discriminator — the load-bearing, un-backstopped string redaction) + `test_web_skeleton` (`_collect_pseudo`, join).
- **Parallel-index pin** → extended `WANT_STYLES`↔`styles[i]` alignment for `content`.
- **Firewall** → `cf.audit_bundle` clean on a pseudo bundle; external-url-in-content canary trips.
- **Round-trip** → `bundle_writer` test (raw string absent on disk).
- **Synthetic host gate** → extended `fixtures/css_style/run_css_style.py` (deterministic, offline, local-server; host Bash, `dangerouslyDisableSandbox=true` — CDP unreachable from the ctx sandbox).
- **Real-site validation** → one-off host run (above), content-free, recorded in §C9-R-P8.

## Mechanical risk — the parallel-index contract

`WANT_STYLES` defines the column order of `captureSnapshot` `computedStyles`; `layout.styles[i]` rows are parallel. `content` is APPENDED after the cut-2 block — existing indices stay stable. The pin test is extended to cover the `content` column. **Join risk:** a pseudo's style must attach to the correct originating node; the join is a direct `dom_to_id[parentIndex]` lookup and a unit test pins a `::before` to its exact parent id (and confirms an orphan pseudo on an unemitted parent is dropped, not misattached).

## Honest ceilings (documented, not force-handled)

- `::placeholder`/`::selection`/`::first-line`/`::first-letter`/`::backdrop` are not enumerated by `captureSnapshot` (empirical) → not captured.
- A pseudo whose originating element is dropped by `classify` (role `None`, not emitted) is dropped — never reattached to an ancestor (a `::before` on a removed wrapper is not the grandparent's `::before`).
- `counter()`/`counters()` identifier names are kept verbatim (mechanism); an author who encodes content in a counter NAME is a pathological single-engine edge, not handled.
- **Pseudo geometry is NOT captured** — `_collect_style` reads `STYLE_PROPS`, which excludes `width`/`height`/`display`, so a pseudo's box size/position is not recorded (only its visual-style + colors + `content`). The pseudo node's bbox exists in the snapshot, so this is a trivial deferred follow-on, not a hard limit.
- Resolved values (incl. `content`) are Chromium's single-engine resolved strings.
- `content` string redaction is un-backstopped by the firewall (the audit catches only url/binary vectors) — correctness rests on the redactor unit tests + the round-trip "raw string absent" assertion.

## Commits

Single-line messages, no trailers. Stage files explicitly by path. One commit per task. Local on master — do NOT push.
