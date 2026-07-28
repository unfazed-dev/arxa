# Firewall audit data-URI backstop — encoding-agnostic — DESIGN

**Status:** design / pre-build. Approved 2026-06-03.
**Scope:** one regex broaden + audit tests. Defense-in-depth, NOT an active-leak fix (see §1).

---

## 1. Honest framing (de-risk read, already done)

A code read corrected the initial premise. This is **not** an active content leak — it is a
**lagging audit backstop**, hardened for symmetry + future-proofing.

- **No active path to disk.** `web_skeleton.parse_snapshot` (web_skeleton.py:325-338) emits exactly
  these per-node fields: `dom_index, tag, bbox, z, style, text, substrate, pseudo, backend, href`.
  The ONLY captured attribute is `href` (anchors only) — a `content_firewall.CONTENT_KEY`, stripped
  on emit by `redact_node`. No `src`/`srcset`/`poster`/`xlink`/custom-property/`cssText` capture exists.
- **url()-wrapped data: already neutralized, any encoding.** `_style._is_external` (_style.py:35)
  matches `t.startswith("data:")` regardless of base64-vs-url-encoded, so `redact_style_value`
  rewrites every `url(data:…)` (in `style`, pseudo `content`, theme/responsive/form-state/container/
  reduced-motion deltas, and `@keyframes` frame props) to `url("<asset>")`. A *bare* (non-`url()`)
  data: URI is invalid CSS and never produced by CDP computed-style capture.
- **The real asymmetry:** the audit signature `_DATA_URI` (content_firewall.py:50) is **base64-only**
  (`data:…;base64,`), weaker than the redactor it is supposed to independently back. If a FUTURE
  capture path ever emitted a bare/unwrapped non-base64 data: URI, construction could miss it AND the
  audit would pass it silently. `audit_bundle` is "THE invariant" (content_firewall.py:166) — its
  backstop should match, not lag, the redactor's coverage.

This reframe (catching the "active leak / ships arbitrary content" overstatement before building on
it) applies the nav-review overselling lesson to our own framing.

## 2. What changes

**`scripts/content_firewall.py` — one line.** Broaden `_DATA_URI` from base64-only to
encoding-agnostic. Current:

```python
_DATA_URI = re.compile(r"data:[a-zA-Z0-9.+-]*/?[a-zA-Z0-9.+-]*;base64,", re.I)
```

New:

```python
# Any data: URI, ANY encoding (base64 / url-encoded / ;utf8 / plain). A real data URI is
# `data:[<mediatype>][;base64],<payload>` — the comma after the metadata is mandatory and is the
# unambiguous discriminator. Matches the encoding-agnostic coverage of _style._is_external (the
# redactor this audit backstops); base64-only lagged it. Linear (one char-class run + literal comma,
# no backtracking → no ReDoS). Zero false-positive: a JSON key `"data":` is `data` + `"` + `:` (quote
# breaks `data:`); `metadata,` has no `data:`; `data: foo, bar` (space after colon) stops the run
# before the comma. Metadata charset covers type/subtype + `;charset=…;base64` params.
_DATA_URI = re.compile(r"data:[a-zA-Z0-9.+/;=_-]*,", re.I)
```

Nothing else changes. The violation `kind` stays `"data-uri"`. Construction is already correct and is
NOT touched.

## 3. Testing — `scripts/test_content_firewall.py` (additive)

Each seeds a string into a file under a temp bundle dir and asserts `audit_bundle` behavior.

1. **url-encoded inline SVG** `data:image/svg+xml,%3Csvg%3E%3C/svg%3E` → flags `data-uri`.
2. **`;utf8,` SVG** `data:image/svg+xml;utf8,<svg/>` → flags `data-uri`.
3. **short text/plain** `data:text/plain,Buy` (below the `_PROSE` 24-char floor, so this proves the
   *data-uri* rule fires, not prose) → flags `data-uri`.
4. **empty metadata** `data:,` → flags `data-uri`.
5. **regression — base64 still caught** `data:image/png;base64,iVBORw0KGgo=` → flags `data-uri`.
6. **zero false-positive** a JSON bundle file containing key `"data": "value"` and the word
   `metadata` and `cursor: pointer` → NO `data-uri` violation.

## 4. Scope cuts (YAGNI)

- **Construction unchanged** — `_is_external` already encoding-agnostic; redacting at capture is not
  re-touched.
- **No new capture fields** — this does not add srcset/custom-property capture (those are the
  hypothetical future paths this backstop now guards; building them is out of scope).
- **No subagent pipeline** — a regex + 6 tests is implemented inline TDD; a multi-task dispatch would
  be process for its own sake.
