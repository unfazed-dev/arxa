# Regime-1 CSS property coverage (cut 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture high-impact visual CSS the tool currently drops (`filter`, `backdrop-filter`, per-node `box-shadow`, full border + corner radii, `transform-origin`, `clip-path`, `mix-blend-mode`, `background-image`) as a content-free per-node `style` field of resolved values.

**Architecture:** `web_skeleton` (content-blind capture) reads the new properties via its existing `DOMSnapshot` `WANT_STYLES` whitelist and emits a RAW `sk["_node_style"]` sidecar (mirroring `_node_colors`, incl. `url()`). A new pure core `_style.py` redacts only external/`data:` `url()` (keeping same-doc `#fragment` mechanism refs). `bundle_writer` pops the sidecar, redacts, and attaches a per-node `style` field (which survives `cf.redact_node`'s content-key blacklist), then the firewall audits.

**Tech Stack:** Python 3.13, stdlib only. CDP `DOMSnapshot.captureSnapshot`. pytest. Firewall (`content_firewall`).

**Design spec:** `docs/plans/regime1-css-property-coverage-design.md` (approved 2026-05-31). Firewall pre-de-risked in sandbox (external/`data:` `url()` trip `content-url`/`data-uri`; gradients/shadows/enums/same-doc `#refs` all clean).

**Standing constraints:** Commits single-line, no trailers. Stage files explicitly by path (never `git add -A`/`.`). One commit per task. Local on master — do NOT push. Host gate runs on host Bash with `dangerouslyDisableSandbox=true`. Content-free invariant.

---

## File Structure

- **`scripts/_style.py`** (new) — pure core: `redact_style_value(value)`, `redact_node_styles(style_map)`, private `_is_external`. No browser/I/O.
- **`scripts/web_skeleton.py`** (modify) — extend `WANT_STYLES`; add `STYLE_PROPS` + `_collect_style(st)`; `to_skeleton` returns a 3-tuple incl. `node_style`; `_snapshot_skeleton` attaches `sk["_node_style"]`. Update all 4 `to_skeleton(` callers.
- **`scripts/bundle_writer.py`** (modify) — `apply_node_style(nodes, node_style)`; `assemble(..., node_style=None)`; `main()` pops `_node_style`.
- **`scripts/test_style.py`** (new), **`scripts/test_web_skeleton.py`** (modify), **`scripts/test_bundle_writer.py`** (modify), **`scripts/test_content_firewall.py`** (modify).
- **`fixtures/css_style/run_css_style.py`** (new) + **`.gitignore`** (modify).

---

## Task 1: `_style.py` — url-redaction pure core

**Files:** Create `scripts/_style.py`, `scripts/test_style.py`.

- [ ] **Step 1: Write the failing tests** — create `scripts/test_style.py`:

```python
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _style import redact_style_value, redact_node_styles  # noqa: E402


def test_no_url_passthrough():
    assert redact_style_value("blur(10px)") == "blur(10px)"
    assert redact_style_value("polygon(0% 0%, 100% 0%, 100% 75%)") == "polygon(0% 0%, 100% 0%, 100% 75%)"


def test_external_https_url_redacted():
    assert redact_style_value('url("https://cdn.example.com/x.png")') == 'url("<asset>")'


def test_external_http_and_protocol_relative_redacted():
    assert redact_style_value('url("http://a/b.png")') == 'url("<asset>")'
    assert redact_style_value('url("//cdn/a.png")') == 'url("<asset>")'


def test_data_uri_redacted():
    assert redact_style_value('url("data:image/png;base64,AAAA")') == 'url("<asset>")'


def test_same_doc_fragment_kept():
    assert redact_style_value('url("#blur")') == 'url("#blur")'
    assert redact_style_value("url(#clip-shape)") == "url(#clip-shape)"


def test_layered_value_redacts_only_external_url():
    v = 'linear-gradient(135deg, rgb(1, 2, 3) 0%, rgb(4, 5, 6) 100%), url("https://a/b.png")'
    out = redact_style_value(v)
    assert "linear-gradient(135deg, rgb(1, 2, 3) 0%, rgb(4, 5, 6) 100%)" in out
    assert 'url("<asset>")' in out and "https://a/b.png" not in out


def test_mixed_internal_and_external_urls():
    v = 'url("#mask"), url("https://a/b.png")'
    out = redact_style_value(v)
    assert 'url("#mask")' in out and 'url("<asset>")' in out and "https" not in out


def test_idempotent():
    once = redact_style_value('url("https://a/b.png")')
    assert redact_style_value(once) == once


def test_redact_node_styles_maps_each_value():
    m = {"filter": "blur(2px)", "background-image": 'url("https://a/b.png")',
         "clip-path": "url(#c)"}
    assert redact_node_styles(m) == {
        "filter": "blur(2px)", "background-image": 'url("<asset>")', "clip-path": "url(#c)"}


def test_redact_node_styles_none_safe():
    assert redact_node_styles(None) is None
    assert redact_node_styles({}) == {}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python -m pytest test_style.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_style'`.

- [ ] **Step 3: Write `scripts/_style.py`**

```python
#!/usr/bin/env python3
"""_style — pure core for Regime-1 per-node CSS style redaction (no browser, no I/O).

web_skeleton captures resolved CSS values RAW (incl. url()) into a `_node_style`
sidecar; this module redacts the ONE content vector at packaging time: a url()
pointing at an EXTERNAL (http/https/protocol-relative) or data: asset becomes the
content-free marker url("<asset>"). A same-document #fragment ref (filter:url(#f),
clip-path:url(#c)) is MECHANISM and is kept verbatim. Everything else (gradients,
shapes, shadows, enums, metrics) is content-free as captured. Empirically grounded:
the firewall flags external/data url() (content-url/data-uri) and passes #fragment
refs + the "<asset>" marker. Deterministic; unit-tested; bundle_writer wraps it."""
from __future__ import annotations
import re

# A url() token: optional matching quote, then the target up to the close paren.
_URL = re.compile(r"""url\(\s*(['"]?)(.*?)\1\s*\)""", re.I | re.S)
_ASSET = 'url("<asset>")'


def _is_external(target):
    """True if a url() target is an external/data asset (content) rather than a
    same-document #fragment ref (mechanism)."""
    t = (target or "").strip().strip("'\"").lower()
    return (t.startswith("http://") or t.startswith("https://")
            or t.startswith("//") or t.startswith("data:"))


def redact_style_value(value):
    """Replace every external/data: url(...) token in a resolved CSS value with the
    content-free marker url("<asset>"); keep same-doc #fragment url() and all other
    tokens verbatim. Returns the input unchanged when no external url() is present
    (idempotent — the marker has no external target)."""
    if not value or "url(" not in value.lower():
        return value

    def _repl(m):
        return _ASSET if _is_external(m.group(2)) else m.group(0)

    return _URL.sub(_repl, value)


def redact_node_styles(style_map):
    """Redact every value in a {prop: resolved_value} map. None/empty-safe."""
    if not style_map:
        return style_map
    return {k: redact_style_value(v) for k, v in style_map.items()}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python -m pytest test_style.py -q`
Expected: 10 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add _style url-redaction core (external/data url -> <asset>, keep #frag refs)"
```

---

## Task 2: `web_skeleton` — capture the new properties into a `_node_style` sidecar

**Files:** Modify `scripts/web_skeleton.py`, `scripts/test_web_skeleton.py`.

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_web_skeleton.py`:

```python
def test_collect_style_sparse_drops_noop_and_zero():
    st = {"filter": "none", "backdrop-filter": "blur(8px)", "clip-path": "none",
          "box-shadow": "none", "mix-blend-mode": "normal",
          "border-top-width": "0px", "border-right-width": "2px",
          "border-top-style": "none", "border-right-style": "dashed",
          "border-right-color": "rgb(1, 2, 3)",
          "border-top-left-radius": "0px", "border-top-right-radius": "8px",
          "transform": "none", "transform-origin": "200px 130px"}
    out = ws._collect_style(st)
    # kept: effective values only
    assert out["backdrop-filter"] == "blur(8px)"
    assert out["border-right-width"] == "2px"
    assert out["border-right-style"] == "dashed"
    assert out["border-right-color"] == "rgb(1, 2, 3)"
    assert out["border-top-right-radius"] == "8px"
    # dropped: none/normal/0/empty + transform-origin (transform is none)
    for k in ("filter", "clip-path", "box-shadow", "mix-blend-mode",
              "border-top-width", "border-top-style", "border-top-left-radius",
              "transform-origin"):
        assert k not in out


def test_collect_style_transform_origin_only_with_transform():
    st = {"transform": "matrix(1, 0, 0, 1, 10, 20)", "transform-origin": "50px 60px"}
    assert ws._collect_style(st)["transform-origin"] == "50px 60px"


def test_collect_style_keeps_raw_url_unredacted():
    # capture is content-BLIND: url() is kept RAW here; redaction is bundle_writer's job.
    st = {"background-image": 'url("https://cdn/x.png")', "clip-path": "url(#c)"}
    out = ws._collect_style(st)
    assert out["background-image"] == 'url("https://cdn/x.png")'
    assert out["clip-path"] == "url(#c)"


def test_want_styles_includes_new_visual_props():
    for k in ("filter", "backdrop-filter", "-webkit-backdrop-filter", "clip-path",
              "box-shadow", "mix-blend-mode", "transform-origin",
              "border-left-style", "border-bottom-color", "border-bottom-left-radius"):
        assert k in ws.WANT_STYLES


def test_want_styles_parallel_index_stable_after_extension():
    # The WANT_STYLES order is the parse_snapshot contract: style row column k maps
    # to WANT_STYLES[k]. A synthetic row of "v<k>" must decode back by name.
    row = [f"v{k}" for k in range(len(ws.WANT_STYLES))]
    S = [""] + row  # strings table; index 0 = "", row strings at 1..N
    srow = [S.index(v) for v in row]
    snap = {"strings": S, "documents": [{
        "nodes": {"nodeName": [S.index("") if "" in S else 0], "parentIndex": [-1]},
        "layout": {"nodeIndex": [0], "bounds": [[0, 0, 10, 10]], "styles": [srow]}}]}
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES)
    style = recs[0]["style"]
    for k, name in enumerate(ws.WANT_STYLES):
        assert style[name] == f"v{k}"


def test_to_skeleton_emits_node_style_for_styled_node():
    # a styled box node -> node_style entry; capture keeps url() raw.
    recs = [{"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
             "z": 0, "text": None, "substrate": None,
             "style": {"display": "block", "filter": "blur(4px)",
                       "background-image": 'url("https://cdn/x.png")'}}]
    sk, node_colors, node_style = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    nid = sk["nodes"][0]["id"]
    assert node_style[nid]["filter"] == "blur(4px)"
    assert node_style[nid]["background-image"] == 'url("https://cdn/x.png")'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python -m pytest test_web_skeleton.py -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute '_collect_style'` (and the new WANT_STYLES / to_skeleton-arity tests fail).

- [ ] **Step 3: Extend `WANT_STYLES`** — replace the `WANT_STYLES = [ ... ]` list (lines ~20-31) by APPENDING a new block at the end (do NOT reorder existing entries — the order is the parallel-index contract):

```python
WANT_STYLES = [
    "font-size", "font-weight", "line-height", "letter-spacing",
    "font-family", "text-align", "color", "background-color",
    "background-image", "border-top-width", "border-top-color", "border-radius",
    "opacity", "display", "visibility", "position", "z-index", "transform",
    # sizing-behavior inputs (spec §4):
    "flex-direction", "flex-grow", "flex-shrink", "flex-basis",
    "align-self", "align-items", "justify-content", "gap",
    "padding-top", "padding-right", "padding-bottom", "padding-left",
    "grid-template-columns", "grid-template-rows",
    "width", "height", "min-width", "max-width", "box-sizing",
    # Regime-1 visual-style props (cut 1). APPENDED — keeps every existing index
    # stable. Captured RAW (incl url()); redacted at packaging (_style/bundle_writer).
    "filter", "backdrop-filter", "-webkit-backdrop-filter",
    "clip-path", "box-shadow", "mix-blend-mode", "transform-origin",
    "border-right-width", "border-bottom-width", "border-left-width",
    "border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
    "border-right-color", "border-bottom-color", "border-left-color",
    "border-top-left-radius", "border-top-right-radius",
    "border-bottom-right-radius", "border-bottom-left-radius",
]
```

- [ ] **Step 4: Add `STYLE_PROPS` + `_collect_style`** — insert immediately AFTER the `WANT_STYLES` list (before `def parse_snapshot`):

```python
# Per-node visual-style props emitted onto node["style"] (Regime-1 cut 1). bg/fg and
# border-top-color stay in the _node_colors sidecar (palette token_ref) and are NOT
# duplicated here. transform-origin is handled separately (only when a transform is set).
STYLE_PROPS = [
    "filter", "backdrop-filter", "-webkit-backdrop-filter",
    "background-image", "clip-path", "box-shadow", "mix-blend-mode",
    "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
    "border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
    "border-right-color", "border-bottom-color", "border-left-color",
    "border-top-left-radius", "border-top-right-radius",
    "border-bottom-right-radius", "border-bottom-left-radius",
]
_STYLE_NOOP = {None, "", "none", "normal", "auto"}


def _collect_style(st):
    """Sparse per-node visual style from resolved CSS. Emits a prop only when it has
    visual effect: none/normal/auto/empty dropped; zero -width/-radius dropped;
    transform-origin only when `transform` is set (else it is the irrelevant default
    pivot). Values are RAW (url() redacted later at packaging). {} when nothing set."""
    out = {}
    for p in STYLE_PROPS:
        v = st.get(p)
        if v is None or (isinstance(v, str) and v.strip().lower() in _STYLE_NOOP):
            continue
        if p.endswith(("-width", "-radius")) and (_px(v) or 0.0) == 0.0:
            continue
        out[p] = v
    tr = st.get("transform")
    if tr and tr.strip().lower() not in ("none", ""):
        to = st.get("transform-origin")
        if to and to.strip():
            out["transform-origin"] = to
    return out
```

- [ ] **Step 5: Make `to_skeleton` build + return `node_style`** — in `to_skeleton`:
  1. After `node_colors = {}` (line ~244) add: `node_style = {}`.
  2. After the `node_colors[node["id"]] = {...}` block (line ~279-283) add:

```python
        sv = _collect_style(st)
        if sv:
            node_style[node["id"]] = sv
```
  3. Change the return (line ~301) from `return skeleton, node_colors` to:

```python
    return skeleton, node_colors, node_style
```
  4. Update the docstring's "Returns (skeleton, node_colors)" to "Returns (skeleton, node_colors, node_style)".

- [ ] **Step 6: Attach the sidecar in `_snapshot_skeleton`** — change the `to_skeleton` call + sidecar block (lines ~390-395) from:

```python
    sk, node_colors = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads this; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    return sk, layout, page
```
to:

```python
    sk, node_colors, node_style = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads these; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    sk["_node_style"] = {str(k): v for k, v in node_style.items()}
    return sk, layout, page
```

- [ ] **Step 7: Update the other 3 `to_skeleton` callers in `test_web_skeleton.py`** (arity change):
  - line ~228: `sk, node_colors = ws.to_skeleton(` → `sk, node_colors, _ = ws.to_skeleton(`
  - line ~263: `sk, _ = ws.to_skeleton(` → `sk, _, _ = ws.to_skeleton(`
  - line ~373: `sk, _ = ws.to_skeleton(` → `sk, _, _ = ws.to_skeleton(`

(Use `grep -n "to_skeleton(" test_web_skeleton.py` to confirm the exact call sites before editing.)

- [ ] **Step 8: Run the suite**

Run: `cd scripts && python -m pytest test_web_skeleton.py -q`
Expected: all pass (existing + 6 new). Then `python -c "import web_skeleton"` → no error.

- [ ] **Step 9: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: capture Regime-1 visual CSS into a content-blind _node_style sidecar"
```

---

## Task 3: `bundle_writer` — redact + attach the per-node `style` field

**Files:** Modify `scripts/bundle_writer.py`, `scripts/test_bundle_writer.py`.

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_bundle_writer.py`:

```python
def test_apply_node_style_redacts_and_attaches():
    nodes = [{"id": 0, "role": "box"}, {"id": 1, "role": "box"}]
    node_style = {0: {"filter": "blur(4px)", "background-image": 'url("https://cdn/x.png")',
                      "clip-path": "url(#c)"}}
    bw.apply_node_style(nodes, node_style)
    assert nodes[0]["style"] == {"filter": "blur(4px)",
                                 "background-image": 'url("<asset>")', "clip-path": "url(#c)"}
    assert "style" not in nodes[1]   # no entry -> no field


def test_apply_node_style_none_is_noop():
    nodes = [{"id": 0, "role": "box"}]
    bw.apply_node_style(nodes, None)
    assert "style" not in nodes[0]


def test_assemble_attaches_redacted_style_surviving_redact_node():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_style = {0: {"filter": "blur(4px)", "background-image": 'url("https://cdn/x.png")'}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    style = bundle["skeleton"]["nodes"][0]["style"]
    assert style["filter"] == "blur(4px)"
    assert style["background-image"] == 'url("<asset>")'   # redacted, survived redact_node


def test_write_bundle_with_external_url_style_audits_clean(tmp_path):
    # full round-trip: a _node_style with an EXTERNAL url -> redacted on disk -> audit passes
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None}],
                "_node_style": {"0": {"background-image": 'url("https://cdn.example.com/x.png")',
                                      "clip-path": "url(#c)", "filter": "blur(2px)"}}}
    raw = skeleton.pop("_node_style")
    node_style = {int(k): v for k, v in raw.items()}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    bw.write_bundle(bundle, tmp_path)   # raises ContentLeak if redaction failed
    import json as _json
    disk = _json.loads((tmp_path / "skeleton.json").read_text())
    assert disk["nodes"][0]["style"]["background-image"] == 'url("<asset>")'
    assert disk["nodes"][0]["style"]["clip-path"] == "url(#c)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python -m pytest test_bundle_writer.py -q`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_style'`.

- [ ] **Step 3: Add the import + `apply_node_style`** — at the top of `bundle_writer.py` add `import _style` (next to the other `import`s). Then add, right after `apply_token_refs` (line ~133):

```python
def apply_node_style(nodes, node_style):
    """Attach each node's captured visual-style map as node["style"], with external/
    data: url() redacted by _style. node_style: {node_id: {prop: raw resolved value}}.
    Runs BEFORE cf.redact_node (a content-key blacklist that preserves the `style`
    key). A node with no captured style gets no `style` field."""
    if not node_style:
        return
    for n in nodes:
        sv = node_style.get(n["id"])
        if sv:
            n["style"] = _style.redact_node_styles(sv)
```

- [ ] **Step 4: Thread `node_style` through `assemble`** — change the signature (line ~135) from:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None):
```
to:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None, node_style=None):
```
and add, immediately after the `apply_token_refs(nodes, palette, node_colors)` line (line ~141):

```python
    apply_node_style(nodes, node_style)
```
(This runs before line ~145 `skeleton["nodes"] = [cf.redact_node(n) for n in nodes]`, so the `style` key is present and survives the blacklist.)

- [ ] **Step 5: Pop the sidecar in `main()`** — after the `_node_colors` pop (lines ~203-204) add:

```python
    raw_style = skeleton.pop("_node_style", {})
    node_style = {int(k): v for k, v in raw_style.items()}
```
and pass it to the assemble call (line ~211) by adding `node_style=node_style`:

```python
    bundle = assemble(skeleton, tokens, node_colors, motion_rows,
                      meta_extra={"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                             time.gmtime())},
                      node_style=node_style)
```

- [ ] **Step 6: Run the suite**

Run: `cd scripts && python -m pytest test_bundle_writer.py -q`
Expected: all pass (existing + 4 new). The existing `test_assemble_builds_core_bundle_keys` (bundle key-set) must still pass — `style` is per-node, not a bundle key.

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: redact + attach per-node style field in bundle_writer (pops _node_style)"
```

---

## Task 4: Firewall — a `style`-carrying skeleton audits clean; an un-redacted url trips

**Files:** Modify `scripts/test_content_firewall.py`.

- [ ] **Step 1: Write the tests** — append to `scripts/test_content_firewall.py` (uses the existing `_clean_bundle` helper + `import content_firewall as cf`; `json` is imported there):

```python
def test_audit_passes_skeleton_with_redacted_style(tmp_path):
    # A skeleton.json whose nodes carry a content-free `style` (resolved values:
    # filter/gradient/clip-path #ref/border + a redacted external bg image) audits
    # clean. Same structured-token class as rgb()/box-shadow; the one content vector
    # (external url) is already the url("<asset>") marker.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {
                         "filter": "blur(4px)",
                         "backdrop-filter": "blur(8px)",
                         "background-image": "linear-gradient(135deg, rgb(18, 52, 86) 0%, rgb(240, 240, 240) 100%), url(\"<asset>\")",
                         "clip-path": "url(\"#clip-shape\")",
                         "box-shadow": "rgba(0, 0, 0, 0.2) 0px 4px 8px 0px, rgb(18, 52, 86) 0px 0px 0px 1px inset",
                         "border-right-style": "dashed",
                         "border-right-color": "rgb(1, 2, 3)",
                         "border-top-left-radius": "8px",
                         "transform-origin": "200px 130px",
                         "mix-blend-mode": "multiply"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_external_url_in_style_trips(tmp_path):
    # Proves the redaction is load-bearing: an UN-redacted external image url in a
    # node style MUST trip the firewall (so a regression in _style cannot ship).
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {"background-image": "url(\"https://cdn.example.com/x.png\")"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) != []
```

- [ ] **Step 2: Run the tests**

Run: `cd scripts && python -m pytest test_content_firewall.py -q`
Expected: all pass (existing + 2 new). If `test_audit_passes_skeleton_with_redacted_style` FAILS with a violation, STOP and report the exact violation — do not normalize away (the P5 lesson). If the canary does NOT trip, the firewall isn't catching external urls — STOP and report.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: verify redacted node style audits clean and un-redacted url trips"
```

---

## Task 5: Full suite green

**Files:** none (verification).

- [ ] **Step 1: Run the whole suite** — `cd scripts && python -m pytest -q`
Expected: all pass (prior total + 10 `_style` + 6 web_skeleton + 4 bundle_writer + 2 firewall).

- [ ] **Step 2:** If anything fails, fix it in the owning task's file and re-run. Do not proceed to the host gate with a red suite.

---

## Task 6: Host gate — live capture → package → redact → audit

**Files:** Create `fixtures/css_style/run_css_style.py`. Modify `.gitignore`.

- [ ] **Step 1: Add the gitignore entry** — append to `.gitignore`:

```
fixtures/css_style/_sk.json
fixtures/css_style/_tokens.json
fixtures/css_style/_bundle/
```

- [ ] **Step 2: Create `fixtures/css_style/run_css_style.py`**

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton captures Regime-1 visual CSS into _node_style, and the
full pipeline (web_skeleton -> bundle_writer) redacts external url() while keeping
filter/clip mechanism, producing a content-free `style` on disk that audits clean.

Deterministic, offline: ONE local server serves both the page AND the "external"
image (http://127.0.0.1:port/ext.png), so the external-url redaction path is
exercised without leaving the host. The page's marker node carries filter,
backdrop-filter, clip-path:url(#c) (with an inline <svg><clipPath id=c>), a
linear-gradient background, a full dashed border + per-corner radius, and a known
bg color; a SECOND node carries background-image:url(/ext.png) (the redaction
exerciser). Asserts the bundle's on-disk node style: filter/gradient/clip #ref kept,
the external bg redacted to url("<asset>"). bundle_writer.write_bundle runs the
firewall audit and RAISES on any leak, so a redaction regression fails the gate."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from web_tokens import parse_color  # noqa: E402

MARK_RGB = (18, 52, 86)  # marker node bg; matched via parse_color (format-robust)

# A 1x1 transparent PNG (real magic bytes) served as the "external" asset.
_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c6360000002000154a24f9f0000000049454e44ae426082")

_PAGE = """<!doctype html><meta charset=utf-8><title>css-style-gate</title>
<style>
  body { margin: 0; }
  #mark { width: 320px; height: 180px; margin: 40px;
          background: linear-gradient(135deg, rgb(18,52,86) 0%, rgb(240,240,240) 100%);
          filter: blur(0.5px); backdrop-filter: blur(8px);
          -webkit-backdrop-filter: blur(8px); mix-blend-mode: multiply;
          clip-path: url(#c);
          border-top: 4px dashed rgb(10,20,30); border-right: 4px dashed rgb(10,20,30);
          border-bottom: 4px dashed rgb(10,20,30); border-left: 4px dashed rgb(10,20,30);
          border-radius: 8px 12px 16px 20px; }
  #ext { width: 100px; height: 100px; background-image: url(/ext.png); }
</style>
<svg width=0 height=0><defs><clipPath id=c><circle cx=50 cy=50 r=50/></clipPath></defs></svg>
<div id=mark></div>
<div id=ext></div>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.endswith("/ext.png"):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(_PNG)))
            self.end_headers()
            self.wfile.write(_PNG)
            return
        body = _PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    sk = ROOT / "fixtures" / "css_style" / "_sk.json"
    tok = ROOT / "fixtures" / "css_style" / "_tokens.json"
    bundle = ROOT / "fixtures" / "css_style" / "_bundle"
    tok.write_text(json.dumps({"palette": {}}))
    r = subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                        "--url", url, "--out", str(sk)],
                       cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        return None
    r = subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                        "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
                       cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        return None
    return json.loads((bundle / "skeleton.json").read_text())


def _check(disk) -> bool:
    nodes = disk.get("nodes") or []
    styled = [n for n in nodes if n.get("style")]
    print("nodes:", len(nodes), "styled:", len(styled))
    # marker node: gradient bg + filter + clip #ref kept
    mark = None
    for n in styled:
        bi = n["style"].get("background-image") or ""
        if "linear-gradient" in bi and parse_color("rgb(18,52,86)") == MARK_RGB:
            mark = n
            break
    if mark is None:
        print("GATE FAIL: no node carried the gradient marker style")
        return False
    s = mark["style"]
    ok = ("blur" in (s.get("filter") or "") + (s.get("backdrop-filter") or "")
          and s.get("clip-path", "").find("#c") >= 0
          and s.get("mix-blend-mode") == "multiply"
          and any(k.endswith("-style") and s[k] == "dashed" for k in s)
          and any(k.endswith("-radius") for k in s))
    if not ok:
        print("GATE FAIL: marker style incomplete:", json.dumps(s))
        return False
    # the external-bg node: background-image redacted to the asset marker
    ext = [n for n in styled if (n["style"].get("background-image") or "").strip() == 'url("<asset>")']
    if not ext:
        print("GATE FAIL: external background-image not redacted to url(\"<asset>\");",
              json.dumps([n["style"].get("background-image") for n in styled]))
        return False
    print("style ok: filter/backdrop/clip(#c)/blend/border/radius kept; external bg redacted")
    return True


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    disk = _run(f"http://127.0.0.1:{port}/")
    ok = bool(disk) and _check(disk)
    srv.shutdown()
    if ok:
        print("GATE PASS: Regime-1 visual CSS captured + redacted; bundle audits clean.")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 3: Controller runs the gate on host**

Run on host Bash with `dangerouslyDisableSandbox=true`:
`python fixtures/css_style/run_css_style.py`
Expected: `GATE PASS` (exit 0) with a `style ok:` line.

**Live-behavior verification (advisor):** if `clip-path:url(#c)` is captured as an ABSOLUTE url (`url("http://127.0.0.1:port/#c")`) rather than `url("#c")`, the `#c` assertion fails and the external-redaction would wrongly fire on it. If that occurs, `_style._is_external` needs a same-document-fragment carve-out (a url whose post-`#` part is non-empty and whose pre-`#` part equals the page URL → keep). Report it; do not silently broaden redaction.

- [ ] **Step 4: Commit**

```bash
git add fixtures/css_style/run_css_style.py .gitignore
git commit -m "test: add host gate for Regime-1 css style capture + url redaction"
```

---

## Task 7: Docs — CONTEXT.md + capture-gaps + survey

**Files:** Modify `CONTEXT.md`, `docs/plans/probe-runner-engine-capture-gaps.md`, `docs/research/css-capture-completeness.md`.

- [ ] **Step 1: CONTEXT.md — Mechanism glossary entry.** Read `CONTEXT.md`. Find the **Design token** or **Mechanism** glossary entry. Append one sentence to the **Mechanism** entry's prose (it ends `_Avoid_: structure-only (tokens/motion are mechanism too).` — insert before the `_Avoid_` line):

```
Per-node visual CSS (filter, backdrop-filter, box-shadow, full border + corner radii, clip-path, mix-blend-mode, transform-origin, background gradients) is captured content-free as a resolved-value `style` field; an external image `url()` is redacted to a `url("<asset>")` marker at packaging (a same-document `#fragment` mechanism ref is kept).
```

- [ ] **Step 2: capture-gaps doc — results record.** Append to `docs/plans/probe-runner-engine-capture-gaps.md`:

```markdown
## §C9-R-P6 — Results: Regime-1 CSS property coverage (cut 1) LANDED (2026-05-31)

First of the "later acquisition gaps" (source: `docs/research/css-capture-completeness.md`).
Captures high-impact visual CSS the tool dropped, as a content-free per-node `style` field.

- **Properties (cut 1):** filter, backdrop-filter (+`-webkit-`), background-image (gradient
  string), clip-path, box-shadow, mix-blend-mode, transform-origin (only when transform set),
  full border (4-side width/style + right/bottom/left color) + 4-corner radius.
- **Architecture:** content-blind capture — web_skeleton reads via its `WANT_STYLES`
  parallel-index whitelist and emits a RAW `_node_style` sidecar (incl. url()); new pure core
  `_style.py` redacts only external/`data:` url() (→ `url("<asset>")`), keeping same-doc
  `#fragment` mechanism refs; bundle_writer pops the sidecar, redacts, attaches per-node
  `style` (survives `cf.redact_node`'s content-key blacklist), then audits.
- **Firewall (de-risked in sandbox first):** gradients/shadows/enums/`#refs` clean; external/
  `data:` url() trip content-url/data-uri → redacted. Re-verified by a clean test + an
  un-redacted-url canary.
- **Honest ceilings:** external background images → `url("<asset>")` marker (slot-like fill
  point), never the URL/bytes; resolved values are faithful but UNPARSED (gradient/shadow
  structured decomposition deferred — reproduction-side, not acquisition).
- **Deferred (trivial follow-on through the proven pipeline):** background-* longhands, outline,
  text-shadow, overflow/aspect-ratio/object-fit, typography suite, transform-3d, gradient/shadow
  parsers. Regime 2 (pseudo-elements) and Regime 3 (responsive/dark-mode/interactive states)
  are separate gaps.
- **Verified:** pure-core unit tests + parallel-index pin + firewall clean/canary + round-trip +
  host gate (`fixtures/css_style/run_css_style.py`, GATE PASS).

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1 CSS
(cut 1) landed. Remaining: Regime-1 follow-on props; Regime 2 pseudo-elements; Regime 3
responsive/theme/interactive; G2/G3/G7-remaining; iOS/Android/Flutter native.
```

- [ ] **Step 3: survey — mark cut-1 landed.** In `docs/research/css-capture-completeness.md`, add a short note at the top (after the first heading/status line) recording that cut 1 landed:

```markdown
> **Update 2026-05-31 — Regime-1 cut 1 LANDED** (§C9-R-P6): per-node `style` now captures
> filter, backdrop-filter, background-image (gradient), clip-path, box-shadow, mix-blend-mode,
> transform-origin, full border + corner radii; external url() redacted at packaging. Remaining
> Regime-1 rows below are follow-on through the same proven pipeline.
```

- [ ] **Step 4: Commit**

```bash
git add CONTEXT.md docs/plans/probe-runner-engine-capture-gaps.md docs/research/css-capture-completeness.md
git commit -m "docs: record Regime-1 CSS property coverage cut 1 (§C9-R-P6) landed"
```

---

## Final review

After all tasks: dispatch a final code reviewer over the whole implementation (`_style.py`, `web_skeleton.py` diff, `bundle_writer.py` diff, the test files, the host gate). Confirm: content-free invariant held (external url redacted, captured values otherwise content-free); the parallel-index contract intact; `_collect_style` emit rules correct (sparse, transform-origin conditional); `style` survives `redact_node`; no schema/bundle-key change. Then report completion — do NOT push.
```
