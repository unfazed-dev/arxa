# probe-runner Design-Capture Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build probe-runner's universal design-capture engine — `web_skeleton` (geometry + roles + z + font + **sizing/layout** + **parent tree**), `web_tokens` (real palette → semantic roles + type/spacing/radii/shadows), `skeleton_diff` (static-design cert with sizing + tree gates), a **bundle writer** (assemble the portable `bundle/` directory), and the two TAIL verbs `web_vectors` + multi-breakpoint — so any agent can rebuild a captured design, swap all content, and re-skin it.

**Architecture:** `web_skeleton` calls one CDP `DOMSnapshot.captureSnapshot` (via the existing `_web_eval` transport) and turns every layout node into a content-independent record: role + REST bbox + z + font metrics + sizing-behavior (`hug|fill|fixed`) + auto-layout intent (`flex|grid` + direction/gap/pad/justify/align) + a `parent` tree edge. `web_tokens` clusters captured colors into semantic roles. `skeleton_diff` certifies two skeletons match on calibrated-tight geometry/typography/sizing/tree gates. The bundle writer assembles `bundle/{meta,skeleton,tokens,motion}.json + assets/manifest.json`, pre-populating `motion.json` for kasane from the wildwood §3 certified animation table. `web_vectors` (opt-in vtracer) and `--viewports` multi-breakpoint capture are the explicit tail.

**Tech Stack:** Python 3 (stdlib + the existing `_web_eval`/`_common` probe modules; pytest), Chrome DevTools Protocol (`DOMSnapshot`), `web_emu` device emulation (reused, not rebuilt), optional `vtracer` (Rust CLI) for reference traces.

**Spec (source of truth):** `docs/superpowers/specs/2026-05-28-landing-sketch-design.md`. The §5.1–5.3 bundle schema is the interface contract — a SEPARATE plan builds the Dioxus `landing-sketch` crate that consumes this exact bundle; do not change field names without updating that plan.

**Scope:** Engine only. The Dioxus `landing-sketch` crate (spec §7) is a SEPARATE plan and is NOT in this document.

**Paths:**
- Probe-runner working copy scripts dir (the canonical repo, now `unfazed-dev/probe-runner`): `~/Developer/artificial_intelligence/skills/probe-runner/scripts` — call it `$SCR`.
- The 3 propagation copies:
  - working / canonical: `~/Developer/artificial_intelligence/skills/probe-runner/`
  - engineering-pack: `~/Developer/poc-repositories/engineering-pack/.claude/skills/probe-runner/`
  - brainiac: `~/Developer/poc-repositories/brainiac/.claude/skills/probe-runner/`
- Run pytest from `$SCR` with `python3 -m pytest`.
- Existing helpers reused (do NOT reimplement): `_web_eval.py` (`resolve_web_eval`, `navigate`, `add_transport_args` — and `web_emu` device profiles), `_common.py` (`die`, `emit_json`).

**Phases (in dependency order — skeleton → tokens → diff → bundle-writer are the load-bearing core and MUST land before the tail):**
- **A** — `web_skeleton` verb (parse/classify + NEW sizing derivation + parent edge + layout object + extended WANT_STYLES)
- **B** — `web_tokens` verb (palette clustering + semantic-role assignment + scales)
- **C** — `skeleton_diff` cert (geometry + NEW sizing-behavior + parent-tree gates)
- **D** — bundle writer (assemble `bundle/` + motion.json from §3 + assets/manifest slots)
- **E** — `web_vectors` (TAIL — opt-in vtracer reference traces)
- **F** — multi-breakpoint (TAIL — `--viewports` + cross-breakpoint sizing inference)
- **G** — propagate to the 3 probe-runner copies (scripts wholesale, SKILL.md targeted)

---

## File structure (what this plan creates/modifies)

| File | Responsibility | Phase |
|------|----------------|-------|
| `$SCR/web_skeleton.py` | DOMSnapshot capture → content-free skeleton (role + REST bbox + z + font + sizing + layout + parent) | A, F |
| `$SCR/test_web_skeleton.py` | pure unit tests for the parse/classify/sizing/layout/parent/skeleton-assembly funcs | A, F |
| `$SCR/web_tokens.py` | computed colors/styles → semantic palette roles + type/spacing/radii/shadow scales | B |
| `$SCR/test_web_tokens.py` | pure unit tests for clustering + role assignment | B |
| `$SCR/skeleton_diff.py` | certify two skeletons match (geometry + sizing + parent-tree gates) + measured-floor report | C |
| `$SCR/test_skeleton_diff.py` | pure unit tests for iou/node_delta/align/diff incl. sizing-swap + tree-break | C |
| `$SCR/bundle_writer.py` | assemble `bundle/{meta,skeleton,tokens,motion}.json + assets/manifest.json`; motion from §3; slot derivation | D |
| `$SCR/test_bundle_writer.py` | pure unit tests for motion-row anchor matching + slot derivation + assembly | D |
| `$SCR/web_vectors.py` | opt-in vtracer raster→SVG reference traces for `role:svg` nodes (non-certified) | E |
| `$SCR/test_web_vectors.py` | pure unit tests for crop-rect derivation + vtracer availability guard | E |
| engineering-pack + brainiac copies of the above scripts; each repo's `SKILL.md` | propagation | G |

The kasane wildwood §3 motion table is baked as a Python literal inside `bundle_writer.py` (Phase D, Task D1) — it is the kasane-specific motion source; generic captures read motion from a `web_anim`/flipbook pass instead.

---

## Phase A — `web_skeleton` verb

DOMSnapshot.captureSnapshot returns: top-level `strings` (string table) + `documents[]`; each document has `nodes` (parallel arrays: `nodeName`, `nodeValue`, `parentIndex`, … — all string values are indexes into `strings`) and `layout` (`nodeIndex[]` mapping layout-node→dom-node, `bounds[]` = `[x,y,w,h]` CSS px, `styles[][]` = string-indexes in the SAME order as the requested `computedStyles`, `text[]` = string-index or -1, `paintOrders[]`). Pure functions parse + classify + derive sizing/layout/parent; `main()` does the live CDP I/O.

### Task A1: `parse_snapshot` — flatten the DOMSnapshot (with the extended WANT_STYLES)

**Files:**
- Create: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

```python
# test_web_skeleton.py
import web_skeleton as ws

# Extended whitelist: spec §4 base styles PLUS sizing-behavior inputs.
WANT = ws.WANT_STYLES

def _idx(strings, val):
    return strings.index(val)

def _snap():
    # strings table; -1 means "no string"
    S = ["", "DIV", "IMG", "H1", "Hello world", "16px", "700", "24px",
         "normal", "sans-serif", "left", "rgb(0,0,0)", "rgba(0,0,0,0)",
         "none", "0px", "static", "auto", "block", "visible", "flex",
         "row", "1", "0", "stretch", "center", "space-between", "border-box"]
    nodes = {"nodeName": [1, 3, 2], "nodeValue": [-1, -1, -1],
             "parentIndex": [-1, 0, 0]}
    # one style row helper keyed by the WANT_STYLES order
    def row(**kw):
        defaults = {k: _idx(S, "none") if k in ("background-image",) else _idx(S, "0px")
                    for k in WANT}
        # sane neutral defaults
        for k in WANT:
            if k in ("display",): defaults[k] = _idx(S, "block")
            elif k in ("visibility",): defaults[k] = _idx(S, "visible")
            elif k in ("position",): defaults[k] = _idx(S, "static")
            elif k in ("color", "background-color"): defaults[k] = _idx(S, "rgb(0,0,0)")
            elif k in ("text-align",): defaults[k] = _idx(S, "left")
            elif k in ("font-family",): defaults[k] = _idx(S, "sans-serif")
            elif k in ("box-sizing",): defaults[k] = _idx(S, "border-box")
            elif k in ("flex-direction",): defaults[k] = _idx(S, "row")
            elif k in ("flex-grow", "flex-shrink"): defaults[k] = _idx(S, "0")
            elif k in ("width", "height", "flex-basis", "min-width", "max-width"):
                defaults[k] = _idx(S, "auto")
            elif k in ("align-self", "align-items", "justify-content"):
                defaults[k] = _idx(S, "normal") if k == "align-self" else _idx(S, "stretch")
            elif k in ("gap",): defaults[k] = _idx(S, "0px")
            elif k in ("grid-template-columns", "grid-template-rows"):
                defaults[k] = _idx(S, "none")
            else:
                defaults[k] = _idx(S, "0px")
        for k, v in kw.items():
            defaults[k] = _idx(S, v)
        return [defaults[k] for k in WANT]
    layout = {
        "nodeIndex": [0, 1, 2],
        "bounds": [[0, 0, 1440, 35137], [120, 1774, 600, 96], [120, 1900, 480, 320]],
        "paintOrders": [0, 12, 8],
        "text": [-1, _idx(S, "Hello world"), -1],
        "styles": [
            row(display="flex", **{"font-size": "16px", "font-weight": "700"}),
            row(**{"font-size": "16px", "font-weight": "700", "color": "rgb(0,0,0)"}),
            row(**{"font-size": "16px", "font-weight": "700"}),
        ],
    }
    return {"strings": S, "documents": [{"nodes": nodes, "layout": layout}]}

def test_parse_flattens_nodes_with_bbox_text_style():
    recs = ws.parse_snapshot(_snap(), WANT)
    assert len(recs) == 3
    h1 = recs[1]
    assert h1["tag"] == "H1"
    assert h1["bbox"] == {"x": 120.0, "y": 1774.0, "w": 600.0, "h": 96.0}
    assert h1["z"] == 12
    assert h1["text"] == "Hello world"
    assert h1["style"]["font-size"] == "16px"
    assert h1["style"]["font-weight"] == "700"
    img = recs[2]
    assert img["tag"] == "IMG"
    assert img["text"] is None
    assert h1["dom_index"] == 1

def test_want_styles_includes_sizing_inputs():
    for k in ["flex-direction", "flex-grow", "flex-shrink", "flex-basis",
              "align-self", "align-items", "justify-content", "gap",
              "padding-top", "padding-right", "padding-bottom", "padding-left",
              "grid-template-columns", "grid-template-rows",
              "width", "height", "min-width", "max-width", "box-sizing"]:
        assert k in ws.WANT_STYLES
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'WANT_STYLES'`

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""web_skeleton — capture a content-independent design skeleton (role + REST
bbox + font metrics + z-order + sizing-behavior + auto-layout + parent tree) of
any URL via one CDP DOMSnapshot.captureSnapshot. Pure parse/classify/derive
funcs are unit-tested; the CDP capture in main() is live-validated."""
from __future__ import annotations

# spec §4: tight base whitelist PLUS sizing-behavior inputs. Order is the
# contract — layout.styles[i] rows are parallel to this list.
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
]


def parse_snapshot(snap, want_styles):
    strings = snap["strings"]

    def s(idx):
        return strings[idx] if idx is not None and idx >= 0 else None

    out = []
    for doc in snap["documents"]:
        nodes = doc["nodes"]
        layout = doc["layout"]
        names = nodes["nodeName"]
        li_node = layout["nodeIndex"]
        bounds = layout["bounds"]
        styles = layout["styles"]
        ltext = layout.get("text", [])
        paints = layout.get("paintOrders", [])
        for i, dom_i in enumerate(li_node):
            x, y, w, h = bounds[i]
            out.append({
                "dom_index": dom_i,
                "tag": (s(names[dom_i]) or "").upper(),
                "bbox": {"x": round(x, 2), "y": round(y, 2),
                         "w": round(w, 2), "h": round(h, 2)},
                "z": paints[i] if i < len(paints) else 0,
                "style": {want_styles[k]: s(styles[i][k]) for k in range(len(want_styles))},
                "text": s(ltext[i]) if i < len(ltext) else None,
            })
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton parse_snapshot with extended sizing-input WANT_STYLES"
```

### Task A2: `svg_descendants` + `classify` — role assignment

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

```python
def test_classify_roles_and_unknown_fallback():
    # image by tag, image by bg-image, text, box (border), unknown_box, svg, skip zero-area
    def rec(tag, w=10, h=10, text=None, bgimg="none", border="0px", bg="rgba(0,0,0,0)"):
        return {"tag": tag, "bbox": {"x": 0, "y": 0, "w": w, "h": h}, "text": text,
                "style": {"background-image": bgimg, "border-top-width": border,
                          "background-color": bg}}
    assert ws.classify(rec("IMG"), in_svg=False) == "image"
    assert ws.classify(rec("DIV", bgimg='url("a.png")'), in_svg=False) == "image"
    assert ws.classify(rec("P", text="hi"), in_svg=False) == "text"
    assert ws.classify(rec("DIV", border="2px"), in_svg=False) == "box"
    assert ws.classify(rec("DIV"), in_svg=False) == "unknown_box"
    assert ws.classify(rec("PATH"), in_svg=True) == "svg"
    assert ws.classify(rec("DIV", w=0, h=0), in_svg=False) is None

def test_svg_descendants_marks_subtree():
    # nodes: 0 DIV (root), 1 SVG (child of 0), 2 PATH (child of 1)
    snap = {"strings": ["", "DIV", "svg", "path"],
            "documents": [{"nodes": {"nodeName": [1, 2, 3], "parentIndex": [-1, 0, 1]},
                           "layout": {"nodeIndex": [], "bounds": [], "styles": [],
                                      "text": [], "paintOrders": []}}]}
    sset = ws.svg_descendants(snap["documents"][0], snap["strings"])
    assert 1 in sset and 2 in sset and 0 not in sset
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_classify_roles_and_unknown_fallback test_web_skeleton.py::test_svg_descendants_marks_subtree -v`
Expected: FAIL — `classify` / `svg_descendants` not defined

- [ ] **Step 3: Write minimal implementation**

```python
IMG_TAGS = {"IMG", "PICTURE", "VIDEO", "CANVAS", "SOURCE"}
_TRANSPARENT = {None, "", "transparent", "rgba(0, 0, 0, 0)", "rgba(0,0,0,0)"}


def svg_descendants(doc, strings):
    """Set of dom indexes that are an <svg> or live inside one."""
    nodes = doc["nodes"]
    names = nodes["nodeName"]
    parent = nodes["parentIndex"]
    out = set()
    n = len(names)
    for i in range(n):
        j = i
        while j is not None and j >= 0:
            if (strings[names[j]] or "").lower() == "svg":
                out.add(i)
                break
            j = parent[j]
    return out


def classify(rec, in_svg):
    b = rec["bbox"]
    if b["w"] <= 0 or b["h"] <= 0:
        return None
    tag = rec["tag"]
    st = rec["style"]
    if tag == "SVG" or in_svg:
        return "svg"
    if tag in IMG_TAGS:
        return "image"
    bg = st.get("background-image")
    if bg and bg != "none" and "url(" in bg:
        return "image"
    if rec.get("text") and rec["text"].strip():
        return "text"
    if (st.get("border-top-width") or "0px") != "0px":
        return "box"
    if st.get("background-color") not in _TRANSPARENT:
        return "box"
    return "unknown_box"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton role classifier and svg-subtree detection with unknown_box fallback"
```

### Task A3: `derive_sizing` — `hug | fill | fixed` from computed CSS (spec §5.1)

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

```python
def test_derive_sizing_fill_hug_fixed():
    def st(**kw):
        base = {"width": "auto", "height": "auto", "flex-grow": "0",
                "flex-shrink": "1", "align-self": "auto", "position": "static",
                "display": "block"}
        base.update(kw)
        return base
    # width:100% -> fill
    assert ws.derive_sizing(st(width="100%"), axis="w") == ("fill", "high")
    # flex-grow > 0 -> fill
    assert ws.derive_sizing(st(**{"flex-grow": "1"}), axis="w") == ("fill", "high")
    # align-self:stretch -> fill (cross axis grow)
    assert ws.derive_sizing(st(**{"align-self": "stretch"}), axis="h") == ("fill", "high")
    # width:auto + shrinks to content -> hug
    assert ws.derive_sizing(st(width="auto"), axis="w") == ("hug", "high")
    # explicit px -> fixed
    assert ws.derive_sizing(st(width="240px"), axis="w") == ("fixed", "high")
    # explicit rem -> fixed
    assert ws.derive_sizing(st(width="20rem"), axis="w") == ("fixed", "high")
    # height analogous: explicit px fixed, auto hug
    assert ws.derive_sizing(st(height="120px"), axis="h") == ("fixed", "high")
    assert ws.derive_sizing(st(height="auto"), axis="h") == ("hug", "high")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_derive_sizing_fill_hug_fixed -v`
Expected: FAIL — `derive_sizing` not defined

- [ ] **Step 3: Write minimal implementation**

```python
import re

_PCT = re.compile(r"^\s*100(\.0+)?%\s*$")
_LEN = re.compile(r"^\s*-?[0-9.]+(px|rem|em|vw|vh|vmin|vmax)\s*$")


def derive_sizing(st, axis):
    """Map computed CSS to hug|fill|fixed for one axis ('w'|'h'). spec §5.1:
    width:100% / flex-grow>0 / align-self:stretch -> fill;
    width:auto + shrink-to-content -> hug; explicit length -> fixed."""
    prop = "width" if axis == "w" else "height"
    val = (st.get(prop) or "auto").strip()

    def _num(x):
        try:
            return float(x)
        except (TypeError, ValueError):
            return 0.0

    grow = _num(st.get("flex-grow"))
    align_self = (st.get("align-self") or "auto").strip()

    # fill: explicit 100%, or flex-grow on the main axis, or stretch on cross
    if _PCT.match(val):
        return ("fill", "high")
    if grow > 0:
        return ("fill", "high")
    if align_self == "stretch":
        return ("fill", "high")
    # fixed: an explicit length
    if _LEN.match(val):
        return ("fixed", "high")
    # auto / min-content / max-content -> hug (shrink to content)
    if val in ("auto", "min-content", "max-content", "fit-content"):
        return ("hug", "high")
    # anything else (calc(), unknown) -> hug, flagged low
    return ("hug", "low")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton sizing derivation hug fill fixed from computed CSS"
```

### Task A4: `derive_layout` — auto-layout intent object (spec §5.1 `layout`)

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

```python
def test_derive_layout_flex_grid_block():
    def st(**kw):
        base = {"display": "block", "flex-direction": "row", "gap": "0px",
                "justify-content": "normal", "align-items": "normal",
                "padding-top": "0px", "padding-right": "0px",
                "padding-bottom": "0px", "padding-left": "0px",
                "grid-template-columns": "none", "grid-template-rows": "none"}
        base.update(kw)
        return base
    flex = ws.derive_layout(st(display="flex", **{"flex-direction": "row", "gap": "24px",
            "justify-content": "space-between", "align-items": "center",
            "padding-top": "16px", "padding-right": "24px",
            "padding-bottom": "16px", "padding-left": "24px"}))
    assert flex["mode"] == "flex"
    assert flex["direction"] == "row"
    assert flex["gap"] == 24.0
    assert flex["pad"] == [16.0, 24.0, 16.0, 24.0]
    assert flex["justify"] == "space-between"
    assert flex["align"] == "center"
    assert flex["grid_cols"] is None and flex["grid_rows"] is None

    grid = ws.derive_layout(st(display="grid",
            **{"grid-template-columns": "1fr 1fr 1fr", "grid-template-rows": "auto"}))
    assert grid["mode"] == "grid"
    assert grid["grid_cols"] == "1fr 1fr 1fr"
    assert grid["grid_rows"] == "auto"

    block = ws.derive_layout(st(display="block"))
    assert block["mode"] == "block"

    none_ = ws.derive_layout(st(display="none"))
    assert none_["mode"] == "none"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_derive_layout_flex_grid_block -v`
Expected: FAIL — `derive_layout` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _px(v):
    if not v:
        return None
    m = re.match(r"^(-?[0-9.]+)px$", v.strip())
    return float(m.group(1)) if m else None


def derive_layout(st):
    """Build the spec §5.1 layout object (auto-layout intent) from computed CSS."""
    disp = (st.get("display") or "block").strip()
    if disp == "none":
        mode = "none"
    elif "flex" in disp:
        mode = "flex"
    elif "grid" in disp:
        mode = "grid"
    else:
        mode = "block"
    direction = (st.get("flex-direction") or "row").strip()
    gcols = st.get("grid-template-columns")
    grows = st.get("grid-template-rows")
    pad = [_px(st.get("padding-top")) or 0.0, _px(st.get("padding-right")) or 0.0,
           _px(st.get("padding-bottom")) or 0.0, _px(st.get("padding-left")) or 0.0]
    return {
        "mode": mode,
        "direction": direction,
        "gap": _px(st.get("gap")) or 0.0,
        "pad": pad,
        "justify": (st.get("justify-content") or "normal").strip(),
        "align": (st.get("align-items") or "normal").strip(),
        "grid_cols": gcols if (gcols and gcols != "none") else None,
        "grid_rows": grows if (grows and grows != "none") else None,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton layout-intent derivation for flex grid block"
```

### Task A5: `build_parent_map` — dom-index → emitted-node parent edge (spec §5.1 `parent`)

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

The skeleton's `parent` is the id of the nearest *emitted* ancestor node (not every DOM node becomes a node — zero-area / unclassified DOM nodes are skipped). So we walk the DOM `parentIndex` chain from each record's `dom_index` until we hit a dom_index that maps to an emitted node.

- [ ] **Step 1: Write the failing test**

```python
def test_build_parent_map_nearest_emitted_ancestor():
    # dom tree: 0 (root, emitted id=0) -> 1 (skipped) -> 2 (emitted id=1)
    # parentIndex by dom index: [-1, 0, 1]
    parent_index = [-1, 0, 1]
    # emitted nodes carry their source dom_index; id is their position
    emitted = [{"id": 0, "dom_index": 0}, {"id": 1, "dom_index": 2}]
    pm = ws.build_parent_map(emitted, parent_index)
    assert pm[0] is None          # root -> no parent
    assert pm[1] == 0             # dom 2's nearest emitted ancestor is dom 0 (id 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_build_parent_map_nearest_emitted_ancestor -v`
Expected: FAIL — `build_parent_map` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def build_parent_map(emitted, parent_index):
    """Map each emitted node id -> the id of its nearest emitted DOM ancestor
    (None for the root). emitted: list of dicts with 'id' + 'dom_index'."""
    dom_to_id = {n["dom_index"]: n["id"] for n in emitted}
    out = {}
    for n in emitted:
        j = parent_index[n["dom_index"]]
        pid = None
        while j is not None and j >= 0:
            if j in dom_to_id:
                pid = dom_to_id[j]
                break
            j = parent_index[j]
        out[n["id"]] = pid
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton parent-tree edge to nearest emitted ancestor"
```

### Task A6: `to_skeleton` — assemble the full §5.1 node schema (LOCKED contract)

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

This task locks the `skeleton.json` node schema to spec §5.1 exactly. Every node carries: `id, role, confidence, bbox, z, parent, sizing, layout`. Text nodes additionally carry `font` + `text_len`. Every node carries `token_ref` (defaulted, filled by bundle writer) and `anim_ref` (default null, filled by bundle writer). Real text strings and image `src` are dropped.

`to_skeleton` returns `(skeleton, node_colors)`: `node_colors` is a `{node_id: {bg, fg, border}}` sidecar of each node's captured colors (raw css), keyed by the SAME emitted node id. This is load-bearing — `skeleton["nodes"]` is filtered (unclassified/zero-area dropped) and reordered relative to the DOM, so colors cannot be re-matched positionally later; they must be captured here, in the same pass, keyed by id. The bundle writer (Phase D) consumes the sidecar to resolve `token_ref`; the crate ignores it.

- [ ] **Step 1: Write the failing test**

```python
def test_to_skeleton_locks_full_schema():
    recs = ws.parse_snapshot(_snap(), WANT)
    svg_set = set()
    # dom parentIndex from _snap(): [-1, 0, 0]
    sk, node_colors = ws.to_skeleton(recs, svg_set, parent_index=[-1, 0, 0],
                        url="https://x/y",
                        viewport={"w": 1440, "h": 887, "dpr": 2},
                        page={"w": 1440, "h": 35137})
    # node_colors sidecar keyed by emitted node id, with bg/fg/border per node
    assert set(node_colors.keys()) == {n["id"] for n in sk["nodes"]}
    for cols in node_colors.values():
        assert set(cols.keys()) == {"bg", "fg", "border"}
    assert sk["schema"] == "probe-skeleton/2"
    assert sk["viewport"] == {"w": 1440, "h": 887, "dpr": 2}
    assert sk["page"] == {"w": 1440, "h": 35137}
    n = sk["nodes"]
    roles = [x["role"] for x in n]
    assert "text" in roles and "image" in roles
    # every node has the locked structural fields
    for node in n:
        assert set(["id", "role", "confidence", "bbox", "z", "parent",
                    "sizing", "layout", "token_ref", "anim_ref"]).issubset(node.keys())
        assert set(node["sizing"].keys()) == {"w", "h", "confidence"}
        assert set(node["layout"].keys()) == {"mode", "direction", "gap", "pad",
                                              "justify", "align", "grid_cols", "grid_rows"}
        assert set(node["token_ref"].keys()) == {"bg", "fg", "border"}
        assert node["anim_ref"] is None
    t = next(x for x in n if x["role"] == "text")
    assert t["font"]["size"] == 16.0          # parsed "16px" -> number
    assert t["font"]["weight"] == 700
    assert t["text_len"] == len("Hello world")  # length only, NOT the content
    assert "text" not in t                       # raw string dropped
    # parent edges: root (id 0) has parent None; children point at it
    root = next(x for x in n if x["parent"] is None)
    assert root["id"] == 0

def test_to_skeleton_drops_content():
    recs = ws.parse_snapshot(_snap(), WANT)
    sk, _ = ws.to_skeleton(recs, set(), parent_index=[-1, 0, 0], url="u",
                           viewport={"w": 1, "h": 1, "dpr": 1}, page={"w": 1, "h": 1})
    blob = repr(sk)
    assert "Hello world" not in blob   # no raw text leaks into the skeleton
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_to_skeleton_locks_full_schema test_web_skeleton.py::test_to_skeleton_drops_content -v`
Expected: FAIL — `to_skeleton` not defined / wrong signature

- [ ] **Step 3: Write minimal implementation**

```python
def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _family(fam):
    f = (fam or "").lower()
    if "mono" in f:
        return "mono"
    if "serif" in f and "sans" not in f:
        return "serif"
    return "sans"


def to_skeleton(recs, svg_set, parent_index, url, viewport, page):
    """Assemble the spec §5.1 content-independent skeleton. token_ref defaults
    are placeholders filled by the bundle writer (web_tokens role mapping);
    anim_ref defaults None, filled by the bundle writer motion post-pass.
    Returns (skeleton, node_colors) where node_colors is {node_id: {bg, fg,
    border}} raw-css — captured here because the nodes list is filtered/reordered
    and colors cannot be re-matched positionally afterward."""
    emitted = []
    node_colors = {}
    for r in recs:
        role = classify(r, in_svg=(r["dom_index"] in svg_set))
        if role is None:
            continue
        st = r["style"]
        sz_w, c_w = derive_sizing(st, axis="w")
        sz_h, c_h = derive_sizing(st, axis="h")
        sz_conf = "low" if "low" in (c_w, c_h) else "high"
        node = {
            "id": len(emitted),
            "role": role,
            "confidence": "low" if role == "unknown_box" else "high",
            "bbox": r["bbox"],
            "z": r["z"],
            "parent": None,  # filled below
            "sizing": {"w": sz_w, "h": sz_h, "confidence": sz_conf},
            "layout": derive_layout(st),
            "token_ref": {"bg": None, "fg": None, "border": None},
            "anim_ref": None,
            "_dom_index": r["dom_index"],  # internal; stripped before emit
        }
        if role == "text":
            size = _px(st.get("font-size"))
            node["font"] = {
                "size": size,
                "weight": int(_num(st.get("font-weight")) or 400),
                "line_height": _px(st.get("line-height")),
                "letter_spacing": _px(st.get("letter-spacing")) or 0.0,
                "family": _family(st.get("font-family")),
                "align": st.get("text-align") or "left",
            }
            node["text_len"] = len((r.get("text") or "").strip())
        node_colors[node["id"]] = {
            "bg": st.get("background-color"),
            "fg": st.get("color"),
            "border": st.get("border-top-color"),
        }
        emitted.append(node)

    pm = build_parent_map(
        [{"id": n["id"], "dom_index": n["_dom_index"]} for n in emitted],
        parent_index,
    )
    for n in emitted:
        n["parent"] = pm[n["id"]]
        del n["_dom_index"]

    skeleton = {
        "schema": "probe-skeleton/2",
        "url": url,
        "viewport": viewport,
        "page": page,
        "nodes": emitted,
    }
    return skeleton, node_colors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton to_skeleton assembling locked content-free schema"
```

### Task A7: `main()` — live CDP capture at REST (I/O, live-validated)

**Files:**
- Modify: `$SCR/web_skeleton.py`

- [ ] **Step 1: Write the I/O wiring** (no unit test — live-validated, per flipbook convention; mirrors `web_flipbook.py` transport handling)

```python
import argparse
import json
import time
from pathlib import Path
from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args

# JS run before capture: jump to top + neutralize scroll-driven transforms so
# DOMSnapshot reads REST bounds (spec §4 capture-state protocol). Kept
# SYNCHRONOUS — `ev.ev` does not awaitPromise; we sleep in Python for the reflow.
_REST_JS = "(() => { window.scrollTo(0, 0); " \
           "if (window.lenis && window.lenis.scrollTo) window.lenis.scrollTo(0, {immediate:true}); " \
           "return true; })()"


def _capture_one(ev, engine, url):
    """Navigate, force REST, capture one DOMSnapshot; return (skeleton, layout,
    page). The skeleton carries a top-level `_node_colors` sidecar (consumed by
    bundle_writer to resolve token_ref; ignored by the crate)."""
    navigate(ev, engine, url)
    ev.ev(_REST_JS)
    time.sleep(0.15)  # let the reflow settle before snapshotting REST bounds

    layout = ev.ev("({w: innerWidth, h: innerHeight, dpr: devicePixelRatio})")
    page = ev.ev("({w: document.documentElement.scrollWidth, "
                 "h: document.documentElement.scrollHeight})")

    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WANT_STYLES,
                         "includeDOMRects": True,
                         "includePaintOrder": True})

    recs = parse_snapshot(snap, WANT_STYLES)
    svg_set = set()
    parent_index = None
    for doc in snap["documents"]:
        svg_set |= svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, node_colors = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": layout["dpr"]},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads this; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    return sk, layout, page


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--out", default=None, help="write skeleton.json here")
    add_transport_args(p)
    args = p.parse_args()

    engine, ev, device = resolve_web_eval(args)
    if not hasattr(ev, "sess"):
        die("web_skeleton needs a CDP transport (chrome host / --android / --cdp-port).")
    sk, _, _ = _capture_one(ev, engine, args.url)
    ev.close()

    if args.out:
        Path(args.out).write_text(json.dumps(sk, indent=2))
        emit_json({"ok": True, "nodes": len(sk["nodes"]), "out": args.out,
                   "viewport": sk["viewport"], "page": sk["page"]})
    else:
        emit_json(sk)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Smoke against a trivial page first**

Start host Chrome with remote debugging, then:
Run: `cd $SCR && python3 web_skeleton.py --url "data:text/html,<h1 style=font-size:32px>hi</h1><img src=x width=100 height=80>" --out /tmp/sk_smoke.json`
Expected: stdout `{"ok": true, "nodes": <n>, ...}`; `/tmp/sk_smoke.json` contains a `text` node (font.size 32) and an `image` node (bbox ~100×80), and every node has `sizing` / `layout` / `parent` keys.

Also confirm `/tmp/sk_smoke.json` has a top-level `_node_colors` object keyed by node id with `bg/fg/border` per node (bundle_writer consumes it).

If field names differ (CDP version skew), inspect once: add a temporary `print(json.dumps(snap)[:1500])` in `_capture_one`, confirm `documents[0].layout` has `nodeIndex/bounds/styles/text/paintOrders` and `documents[0].nodes.parentIndex`, then remove the print.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py
git commit -m "feat: add web_skeleton main DOMSnapshot capture at REST over shared CDP transport"
```

### Task A8: Verify the REST-bbox capture-state on a known kasane element (spec §4 — before schema lock)

**Files:** none (validation only)

- [ ] **Step 1: Capture kasane**

Run: `cd $SCR && python3 web_skeleton.py --url "https://kasane-keyboard.com/craftanddesign" --out /tmp/kasane.json`
Expected: `{"ok": true, "nodes": <hundreds>, "viewport": {...}, "page": {"h": ~35137, ...}}`

- [ ] **Step 2: Assert the hero element reports its known REST y (anchor 1774)**

Run:
```bash
cd $SCR && python3 -c "import json;d=json.load(open('/tmp/kasane.json'));\
imgs=[n for n in d['nodes'] if n['role']=='image' and 1500<n['bbox']['y']<2100];\
print('hero-ish images near y~1774:', [(round(n['bbox']['y']),round(n['bbox']['w']),round(n['bbox']['h']),n['sizing']) for n in imgs][:5])"
```
Expected: at least one image with `y` ≈ 1774 (the wildwood hero-img anchor) and a populated `sizing`. If everything is near y≈0..887 only (i.e. clipped to viewport), the REST protocol failed — fix `_REST_JS` (the page may need a forced reflow or Lenis disabled) BEFORE proceeding. **Do not lock the schema until a below-the-fold element reports its true page-y.**

- [ ] **Step 3: Confirm the captured viewport matches the wildwood §3 cert viewport (height 887px)** and record the actual `viewport.w` into a scratch note for the crate plan. spec §3 windows/amplitudes are valid only at that viewport; if `viewport.h != 887`, re-run under the §3 viewport via the transport's device flag before locking.

### Phase A acceptance
`web_skeleton.py` exists; 9 pure tests pass; live kasane capture produces `kasane.json` with correct below-the-fold REST bboxes, populated `sizing`/`layout`/`parent` on every node, and `page.h ≈ 35137`.

---

## Phase B — `web_tokens` verb

`web_tokens` reads the same DOMSnapshot computed styles (or a skeleton + a colors pass) and produces the spec §5.2 `tokens.json`: a semantic palette (roles assigned by area + frequency + contrast), a type scale, spacing, radii, shadows. Pure functions (clustering + role assignment) are unit-tested; the live capture in `main()` is validated against kasane.

### Task B1: `cluster_colors` — merge near-duplicate hues

**Files:**
- Create: `$SCR/web_tokens.py`
- Test: `$SCR/test_web_tokens.py`

- [ ] **Step 1: Write the failing test**

```python
# test_web_tokens.py
import web_tokens as wt

def test_parse_color_rgb_and_hex():
    assert wt.parse_color("rgb(11, 11, 12)") == (11, 11, 12)
    assert wt.parse_color("rgba(245, 245, 240, 1)") == (245, 245, 240)
    assert wt.parse_color("#0b0b0c") == (11, 11, 12)
    assert wt.parse_color("transparent") is None
    assert wt.parse_color("rgba(0,0,0,0)") is None

def test_cluster_merges_near_duplicates():
    # three near-identical darks + one light: clusters to 2 representatives
    samples = [
        ("rgb(11,11,12)", 1000.0),
        ("rgb(12,12,13)", 50.0),     # within tol of the first
        ("rgb(10,10,11)", 20.0),     # within tol of the first
        ("rgb(245,245,240)", 800.0), # distinct light
    ]
    clusters = wt.cluster_colors(samples, tol=8)
    assert len(clusters) == 2
    # each cluster: (representative_hex, total_area)
    reps = {c[0] for c in clusters}
    # dark cluster total area = 1000+50+20 = 1070, light = 800
    dark = next(c for c in clusters if c[1] > 1000)
    assert dark[1] == 1070.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py -v`
Expected: FAIL — module/functions not defined

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""web_tokens — extract a semantic palette (roles by area/frequency/contrast) +
type scale + spacing + radii + shadows (spec §5.2) from a page's computed styles.
Pure clustering/role funcs are unit-tested; main() is live-validated."""
from __future__ import annotations
import re

_RGB = re.compile(r"rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*([0-9.]+)\s*)?\)")


def parse_color(s):
    """Return (r,g,b) or None for transparent/unparseable."""
    if not s:
        return None
    s = s.strip()
    if s in ("transparent", "none", "currentColor"):
        return None
    m = _RGB.match(s)
    if m:
        a = float(m.group(4)) if m.group(4) is not None else 1.0
        if a == 0.0:
            return None
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    if s.startswith("#"):
        h = s[1:]
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) >= 6:
            return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return None


def _hex(rgb):
    return "#%02x%02x%02x" % rgb


def cluster_colors(samples, tol=8):
    """Merge near-duplicate colors. samples: [(css_color, area), ...].
    Returns [(representative_hex, total_area), ...] sorted by area desc.
    A new sample joins the nearest cluster within Chebyshev distance tol."""
    clusters = []  # each: [r, g, b, total_area, weight]
    for css, area in samples:
        rgb = parse_color(css)
        if rgb is None:
            continue
        best, best_d = None, None
        for c in clusters:
            d = max(abs(c[0] - rgb[0]), abs(c[1] - rgb[1]), abs(c[2] - rgb[2]))
            if d <= tol and (best_d is None or d < best_d):
                best, best_d = c, d
        if best is None:
            clusters.append([rgb[0], rgb[1], rgb[2], area, 1])
        else:
            best[3] += area
    out = [(_hex((int(c[0]), int(c[1]), int(c[2]))), c[3]) for c in clusters]
    out.sort(key=lambda x: x[1], reverse=True)
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_tokens.py scripts/test_web_tokens.py
git commit -m "feat: add web_tokens color parsing and near-duplicate hue clustering"
```

### Task B2: `assign_roles` — semantic palette by area/frequency/contrast (spec §5.2)

**Files:**
- Modify: `$SCR/web_tokens.py`
- Test: `$SCR/test_web_tokens.py`

Role heuristic (spec §5.2): largest-area background → `background`; next container fill → `surface`; most-frequent text color → `fg-primary`; lower-contrast text → `fg-muted`; saturated outlier → `accent`; most-common border color → `border`. Each role flagged with confidence.

- [ ] **Step 1: Write the failing test**

```python
def test_assign_roles_picks_bg_fg_accent():
    # bg samples (by area): dark dominant, then a slightly lighter surface
    bg = [("rgb(11,11,12)", 5000.0), ("rgb(21,21,26)", 1200.0)]
    # text colors (by frequency count): light dominant, a muted grey, a saturated accent
    fg = [("rgb(245,245,240)", 400), ("rgb(154,154,147)", 120), ("rgb(200,85,42)", 30)]
    borders = [("rgb(42,42,48)", 60)]
    roles = wt.assign_roles(bg, fg, borders)
    assert roles["background"]["value"] == "#0b0b0c"
    assert roles["surface"]["value"] == "#15151a"
    assert roles["fg-primary"]["value"] == "#f5f5f0"
    assert roles["fg-muted"]["value"] == "#9a9a93"
    assert roles["accent"]["value"] == "#c8552a"   # saturated outlier
    assert roles["border"]["value"] == "#2a2a30"
    # every role carries a confidence flag
    for r in roles.values():
        assert r["confidence"] in ("high", "low")

def test_assign_roles_low_confidence_when_ambiguous():
    # only one text color -> no muted/accent distinction -> low confidence flags
    bg = [("rgb(11,11,12)", 5000.0)]
    fg = [("rgb(245,245,240)", 400)]
    borders = []
    roles = wt.assign_roles(bg, fg, borders)
    assert roles["surface"]["confidence"] == "low"   # no second bg
    assert roles["fg-muted"]["confidence"] == "low"  # no second text color
    assert roles["accent"]["confidence"] == "low"
    assert roles["border"]["confidence"] == "low"    # no border samples
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py::test_assign_roles_picks_bg_fg_accent test_web_tokens.py::test_assign_roles_low_confidence_when_ambiguous -v`
Expected: FAIL — `assign_roles` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _saturation(rgb):
    mx, mn = max(rgb), min(rgb)
    return 0.0 if mx == 0 else (mx - mn) / mx


def _luma(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def assign_roles(bg_samples, fg_samples, border_samples):
    """Assign spec §5.2 semantic palette roles. Inputs are pre-clustered or raw
    (css, weight) lists. background/surface by area; fg-primary/fg-muted by
    frequency+contrast; accent by saturation outlier; border by frequency."""
    bg = cluster_colors(bg_samples)          # area-weighted, desc
    fg = cluster_colors(fg_samples)          # frequency-weighted, desc
    borders = cluster_colors(border_samples)

    def role(value, conf):
        return {"value": value, "confidence": conf}

    background = role(bg[0][0], "high") if bg else role(None, "low")
    surface = role(bg[1][0], "high") if len(bg) > 1 else role(
        bg[0][0] if bg else None, "low")

    fg_primary = role(fg[0][0], "high") if fg else role(None, "low")
    # fg-muted: the lower-luma-contrast-vs-bg text color among the rest
    bg_l = _luma(parse_color(background["value"])) if background["value"] else 0.0
    rest = fg[1:]
    if rest:
        muted = min(rest, key=lambda c: abs(_luma(parse_color(c[0])) - bg_l))
        fg_muted = role(muted[0], "high")
    else:
        fg_muted = role(fg_primary["value"], "low")

    # accent: the most-saturated text color (outlier), else low conf
    sat_sorted = sorted(fg, key=lambda c: _saturation(parse_color(c[0])), reverse=True)
    if sat_sorted and _saturation(parse_color(sat_sorted[0][0])) > 0.3 and len(fg) > 1:
        accent = role(sat_sorted[0][0], "high")
    else:
        accent = role(sat_sorted[0][0] if sat_sorted else None, "low")

    border = role(borders[0][0], "high") if borders else role(None, "low")

    return {"background": background, "surface": surface,
            "fg-primary": fg_primary, "fg-muted": fg_muted,
            "accent": accent, "border": border}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_tokens.py scripts/test_web_tokens.py
git commit -m "feat: add web_tokens semantic role assignment by area frequency contrast"
```

### Task B3: `build_scales` — type scale + spacing + radii + shadows + families (spec §5.2)

**Files:**
- Modify: `$SCR/web_tokens.py`
- Test: `$SCR/test_web_tokens.py`

- [ ] **Step 1: Write the failing test**

```python
def test_build_scales_dedupes_and_sorts():
    rows = [
        {"font-size": "64px", "font-weight": "700", "border-radius": "12px",
         "padding-left": "24px", "font-family": "Inter, system-ui"},
        {"font-size": "16px", "font-weight": "400", "border-radius": "0px",
         "padding-left": "8px", "font-family": "Inter, system-ui"},
        {"font-size": "16px", "font-weight": "600", "border-radius": "999px",
         "padding-left": "48px", "font-family": "Georgia, serif"},
    ]
    sc = wt.build_scales(rows, shadows=["0 1px 2px rgba(0,0,0,.2)"])
    assert sc["type_scale"] == [16, 64]
    assert sc["weights"] == [400, 600, 700]
    assert sc["radii"] == [0, 12, 999]
    assert 8 in sc["spacing"] and 24 in sc["spacing"] and 48 in sc["spacing"]
    assert sc["families"]["sans"].startswith("Inter")
    assert "serif" in sc["families"]["serif"].lower() or "georgia" in sc["families"]["serif"].lower()
    assert sc["shadows"] == ["0 1px 2px rgba(0,0,0,.2)"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py::test_build_scales_dedupes_and_sorts -v`
Expected: FAIL — `build_scales` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _px_int(v):
    if not v:
        return None
    m = re.match(r"^(-?[0-9.]+)px$", v.strip())
    return int(round(float(m.group(1)))) if m else None


def _family_bucket(fam):
    f = (fam or "").lower()
    if "mono" in f:
        return "mono"
    if "serif" in f and "sans" not in f:
        return "serif"
    return "sans"


def build_scales(rows, shadows=None):
    """rows: list of computed-style dicts. Returns the spec §5.2 scales."""
    sizes, weights, radii, spacing = set(), set(), set(), set()
    families = {}
    for r in rows:
        s = _px_int(r.get("font-size"))
        if s:
            sizes.add(s)
        try:
            w = int(float(r.get("font-weight"))) if r.get("font-weight") else None
        except (TypeError, ValueError):
            w = None
        if w:
            weights.add(w)
        rad = _px_int(r.get("border-radius"))
        if rad is not None:
            radii.add(rad)
        for p in ("padding-top", "padding-right", "padding-bottom", "padding-left", "gap"):
            pv = _px_int(r.get(p))
            if pv:
                spacing.add(pv)
        fam = r.get("font-family")
        if fam:
            families.setdefault(_family_bucket(fam), fam)
    return {
        "type_scale": sorted(sizes),
        "weights": sorted(weights),
        "radii": sorted(radii),
        "spacing": sorted(spacing),
        "families": families,
        "shadows": list(shadows or []),
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_tokens.py scripts/test_web_tokens.py
git commit -m "feat: add web_tokens type spacing radii shadow scale extraction"
```

### Task B4: `main()` — live capture of colors + styles → tokens.json (I/O, live-validated)

**Files:**
- Modify: `$SCR/web_tokens.py`

- [ ] **Step 1: Write the I/O wiring** (no unit test — live-validated)

```python
import argparse
import json
from pathlib import Path
from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args

# Collect per-element area-weighted bg colors, frequency-weighted text colors,
# border colors, and the style rows for scale extraction — one in-page pass.
_COLLECT_JS = r"""
(() => {
  const out = {bg: [], fg: [], border: [], rows: [], shadows: []};
  const els = document.querySelectorAll('*');
  for (const el of els) {
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const area = Math.max(0, r.width) * Math.max(0, r.height);
    if (area > 0) out.bg.push([cs.backgroundColor, area]);
    const txt = (el.textContent || '').trim().length;
    if (txt > 0 && el.children.length === 0) out.fg.push([cs.color, 1]);
    if (parseFloat(cs.borderTopWidth) > 0) out.border.push([cs.borderTopColor, 1]);
    if (cs.boxShadow && cs.boxShadow !== 'none') out.shadows.push(cs.boxShadow);
    out.rows.push({
      'font-size': cs.fontSize, 'font-weight': cs.fontWeight,
      'border-radius': cs.borderTopLeftRadius, 'padding-top': cs.paddingTop,
      'padding-right': cs.paddingRight, 'padding-bottom': cs.paddingBottom,
      'padding-left': cs.paddingLeft, 'gap': cs.gap, 'font-family': cs.fontFamily,
    });
  }
  // dedupe shadows
  out.shadows = Array.from(new Set(out.shadows)).slice(0, 8);
  return out;
})()
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--out", default=None, help="write tokens.json here")
    add_transport_args(p)
    args = p.parse_args()

    engine, ev, device = resolve_web_eval(args)
    if not hasattr(ev, "ev"):
        die("web_tokens needs a web transport.")
    navigate(ev, engine, args.url)
    data = ev.ev(_COLLECT_JS)
    ev.close()

    bg = [(c, a) for c, a in data["bg"]]
    fg = [(c, n) for c, n in data["fg"]]
    border = [(c, n) for c, n in data["border"]]
    roles = assign_roles(bg, fg, border)
    scales = build_scales(data["rows"], shadows=data.get("shadows"))

    tokens = {
        "palette": {k: v["value"] for k, v in roles.items()},
        "palette_confidence": {k: v["confidence"] for k, v in roles.items()},
        "type_scale": scales["type_scale"],
        "weights": scales["weights"],
        "families": scales["families"],
        "spacing": scales["spacing"],
        "radii": scales["radii"],
        "shadows": scales["shadows"],
    }
    if args.out:
        Path(args.out).write_text(json.dumps(tokens, indent=2))
        emit_json({"ok": True, "out": args.out, "palette": tokens["palette"],
                   "confidence": tokens["palette_confidence"]})
    else:
        emit_json(tokens)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Live kasane capture sanity**

Run: `cd $SCR && python3 web_tokens.py --url "https://kasane-keyboard.com/craftanddesign" --out /tmp/kasane_tokens.json`
Expected: `{"ok": true, "palette": {"background": "#...", "surface": "#...", "fg-primary": "#...", ...}, "confidence": {...}}`. Sanity-check that `background` is the dominant page color and `fg-primary` is the dominant text color. Low-confidence roles are acceptable (spec §8 — palette roles are heuristic, flagged, allow human override).

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_tokens.py
git commit -m "feat: add web_tokens main live palette and scale capture to tokens.json"
```

### Phase B acceptance
`web_tokens.py` exists; 5 pure tests pass; live kasane capture produces `tokens.json` with sensible `background`/`fg-primary` roles and per-role confidence flags.

---

## Phase C — `skeleton_diff` cert

`skeleton_diff` certifies two skeletons match on the spec §6 tight gates: geometry (IoU/pos/size), role exact, font exact, sizing-behavior exact (where both high-confidence), and parent-tree-edge agreement. Pure logic; `main()` is a thin CLI. Thresholds are calibrated to the measured self-diff floor (spec §6).

### Task C1: `iou` + `node_delta` — geometry/type/font/sizing deltas

**Files:**
- Create: `$SCR/skeleton_diff.py`
- Test: `$SCR/test_skeleton_diff.py`

- [ ] **Step 1: Write the failing test**

```python
# test_skeleton_diff.py
import skeleton_diff as sd

def test_iou_and_node_delta():
    a = {"x": 0, "y": 0, "w": 100, "h": 100}
    b = {"x": 0, "y": 0, "w": 100, "h": 100}
    assert sd.iou(a, b) == 1.0
    c = {"x": 50, "y": 0, "w": 100, "h": 100}
    assert abs(sd.iou(a, c) - (50*100) / (2*100*100 - 50*100)) < 1e-9

def test_node_delta_flags_font_role_sizing():
    src = {"role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
           "font": {"size": 16.0, "weight": 700},
           "sizing": {"w": "fill", "h": "hug", "confidence": "high"}}
    same = {"role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
            "font": {"size": 16.0, "weight": 700},
            "sizing": {"w": "fill", "h": "hug", "confidence": "high"}}
    d = sd.node_delta(src, same)
    assert d["iou"] == 1.0 and d["role_ok"] and d["font_size_ok"]
    assert d["sizing_w_ok"] and d["sizing_h_ok"]
    # +1% font size FAILS (exact gate)
    bad_font = dict(same, font={"size": 16.16, "weight": 700})
    assert sd.node_delta(src, bad_font)["font_size_ok"] is False
    # sizing swap fill->fixed FAILS when both high-confidence
    bad_sz = dict(same, sizing={"w": "fixed", "h": "hug", "confidence": "high"})
    assert sd.node_delta(src, bad_sz)["sizing_w_ok"] is False
    # sizing diff IGNORED when either side is low-confidence
    lowconf = dict(same, sizing={"w": "fixed", "h": "hug", "confidence": "low"})
    assert sd.node_delta(src, lowconf)["sizing_w_ok"] is True
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: FAIL — module/functions not defined

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""skeleton_diff — certify two web_skeleton outputs match on calibrated-tight
geometry/typography/sizing/tree gates (spec §6). Pure logic; main() is a thin CLI."""
from __future__ import annotations


def iou(a, b):
    ax2, ay2 = a["x"] + a["w"], a["y"] + a["h"]
    bx2, by2 = b["x"] + b["w"], b["y"] + b["h"]
    ix = max(0.0, min(ax2, bx2) - max(a["x"], b["x"]))
    iy = max(0.0, min(ay2, by2) - max(a["y"], b["y"]))
    inter = ix * iy
    union = a["w"] * a["h"] + b["w"] * b["h"] - inter
    return inter / union if union > 0 else 0.0


def _sizing_ok(s, c, axis):
    """sizing on one axis matches IFF both nodes flag sizing high-confidence
    (spec §6: 'sizing.w/sizing.h exact where both are confidence:high')."""
    ss, cs = s.get("sizing"), c.get("sizing")
    if not ss or not cs:
        return True
    if ss.get("confidence") != "high" or cs.get("confidence") != "high":
        return True
    return ss.get(axis) == cs.get(axis)


def node_delta(s, c):
    sb, cb = s["bbox"], c["bbox"]
    sc = (sb["x"] + sb["w"] / 2, sb["y"] + sb["h"] / 2)
    cc = (cb["x"] + cb["w"] / 2, cb["y"] + cb["h"] / 2)
    pos_err = ((sc[0] - cc[0]) ** 2 + (sc[1] - cc[1]) ** 2) ** 0.5
    d = {"iou": iou(sb, cb), "pos_err": pos_err,
         "w_err": abs(sb["w"] - cb["w"]), "h_err": abs(sb["h"] - cb["h"]),
         "role_ok": s["role"] == c["role"], "font_size_ok": True,
         "sizing_w_ok": _sizing_ok(s, c, "w"),
         "sizing_h_ok": _sizing_ok(s, c, "h")}
    if s["role"] == "text" and "font" in s and "font" in c:
        ss, cs = s["font"].get("size"), c["font"].get("size")
        d["font_size_ok"] = (ss is not None and cs is not None and abs(ss - cs) < 1e-6)
    return d
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/skeleton_diff.py scripts/test_skeleton_diff.py
git commit -m "feat: add skeleton_diff iou and node_delta with sizing-behavior gates"
```

### Task C2: `align` — paint-order + nearest-center greedy match

**Files:**
- Modify: `$SCR/skeleton_diff.py`
- Test: `$SCR/test_skeleton_diff.py`

- [ ] **Step 1: Write the failing test**

```python
def test_align_matches_nearest_and_reports_unmatched():
    src = [{"id": 0, "z": 1, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}},
           {"id": 1, "z": 2, "role": "text", "bbox": {"x": 100, "y": 0, "w": 10, "h": 10}}]
    clone = [{"id": 9, "z": 1, "role": "box", "bbox": {"x": 1, "y": 0, "w": 10, "h": 10}}]
    matches, un_src, un_clone = sd.align(src, clone, radius=20)
    assert len(matches) == 1 and matches[0][0]["id"] == 0 and matches[0][1]["id"] == 9
    assert [n["id"] for n in un_src] == [1] and un_clone == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py::test_align_matches_nearest_and_reports_unmatched -v`
Expected: FAIL — `align` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _center(n):
    b = n["bbox"]
    return (b["x"] + b["w"] / 2, b["y"] + b["h"] / 2)


def align(src, clone, radius=24):
    """Greedy nearest-center match, processed in paint (z) order. Returns
    (matches[(s,c)], unmatched_src, unmatched_clone)."""
    src_sorted = sorted(src, key=lambda n: n.get("z", 0))
    remaining = list(clone)
    matches, un_src = [], []
    for s in src_sorted:
        sc = _center(s)
        best, best_d = None, None
        for c in remaining:
            cc = _center(c)
            dist = ((sc[0] - cc[0]) ** 2 + (sc[1] - cc[1]) ** 2) ** 0.5
            if dist <= radius and (best_d is None or dist < best_d):
                best, best_d = c, dist
        if best is not None:
            matches.append((s, best))
            remaining.remove(best)
        else:
            un_src.append(s)
    return matches, un_src, remaining
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/skeleton_diff.py scripts/test_skeleton_diff.py
git commit -m "feat: add skeleton_diff align paint-order nearest-center greedy match"
```

### Task C3: `tree_agreement` — parent-edge agreement across matched nodes (spec §6.3)

**Files:**
- Modify: `$SCR/skeleton_diff.py`
- Test: `$SCR/test_skeleton_diff.py`

Parent-tree-edge agreement (spec §6.3 gate ≥0.99): for each matched (src,clone) pair, the src node's `parent` must map (via the same alignment) to the clone node's `parent`. Fraction of pairs whose parent edge agrees.

- [ ] **Step 1: Write the failing test**

```python
def test_tree_agreement_full_and_broken():
    # src ids 0(root),1(child of 0); clone ids 10(root),11(child of 10)
    src = [{"id": 0, "parent": None}, {"id": 1, "parent": 0}]
    clone = [{"id": 10, "parent": None}, {"id": 11, "parent": 10}]
    # matches map src 0<->clone 10, src 1<->clone 11
    matches = [(src[0], clone[0]), (src[1], clone[1])]
    assert sd.tree_agreement(matches) == 1.0
    # break: clone child claims root has no parent mismatch -> reparent 11 to None
    clone_bad = [{"id": 10, "parent": None}, {"id": 11, "parent": None}]
    matches_bad = [(src[0], clone_bad[0]), (src[1], clone_bad[1])]
    assert sd.tree_agreement(matches_bad) == 0.5  # 1 of 2 edges agree (root edge ok)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py::test_tree_agreement_full_and_broken -v`
Expected: FAIL — `tree_agreement` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def tree_agreement(matches):
    """Fraction of matched pairs whose parent edge agrees: src.parent maps
    (under the alignment) to clone.parent. Both-None counts as agreement."""
    if not matches:
        return 1.0
    src_to_clone = {s["id"]: c["id"] for s, c in matches}
    agree = 0
    for s, c in matches:
        sp, cp = s.get("parent"), c.get("parent")
        if sp is None and cp is None:
            agree += 1
        elif sp is not None and src_to_clone.get(sp) == cp:
            agree += 1
    return agree / len(matches)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/skeleton_diff.py scripts/test_skeleton_diff.py
git commit -m "feat: add skeleton_diff parent-tree-edge agreement metric"
```

### Task C4: `diff` — gates + measured-floor report (spec §6)

**Files:**
- Modify: `$SCR/skeleton_diff.py`
- Test: `$SCR/test_skeleton_diff.py`

- [ ] **Step 1: Write the failing test**

```python
GATES = {"iou": 0.98, "pos": 1.0, "size": 1.0, "matched_frac": 0.99,
         "zrank": 0.99, "tree": 0.99}

def _sk(nodes):
    return {"nodes": nodes}

def _n(id, z, role, x, y, w, h, parent=None, font=None, sizing=None):
    d = {"id": id, "z": z, "role": role,
         "bbox": {"x": x, "y": y, "w": w, "h": h}, "parent": parent}
    if font:
        d["font"] = font
    if sizing:
        d["sizing"] = sizing
    return d

def test_diff_identical_pass():
    nodes = [_n(0, 1, "box", 0, 0, 50, 50),
             _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.0})]
    r = sd.diff(_sk(nodes), _sk(nodes), GATES)
    assert r["pass"] is True
    assert r["measured"]["min_iou"] == 1.0 and r["measured"]["max_pos_err"] == 0.0
    assert r["measured"]["tree"] == 1.0

def test_diff_shift_role_sizing_tree_all_fail():
    base = [_n(0, 1, "box", 0, 0, 50, 50),
            _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.0},
               sizing={"w": "fill", "h": "hug", "confidence": "high"})]
    # 2px shift -> IoU below 0.98
    shifted = [_n(0, 1, "box", 2, 0, 50, 50), base[1]]
    assert sd.diff(_sk(base), _sk(shifted), GATES)["pass"] is False
    # role swap
    swapped = [dict(base[0], role="image"), base[1]]
    assert sd.diff(_sk(base), _sk(swapped), GATES)["pass"] is False
    # sizing swap fill->fixed (both high-conf) -> FAIL
    szswap = [base[0], _n(1, 2, "text", 0, 60, 50, 20, parent=0,
              font={"size": 16.0}, sizing={"w": "fixed", "h": "hug", "confidence": "high"})]
    assert sd.diff(_sk(base), _sk(szswap), GATES)["pass"] is False
    # font-size +1% (exact gate) -> FAIL
    fbad = [base[0], _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.16})]
    assert sd.diff(_sk(base), _sk(fbad), GATES)["pass"] is False
    # tree break: reparent clone child to None
    treebad = [base[0], dict(base[1], parent=None)]
    assert sd.diff(_sk(base), _sk(treebad), GATES)["pass"] is False

def test_diff_unmatched_high_conf_fails_aggregate():
    base = [_n(0, 1, "box", 0, 0, 50, 50),
            _n(1, 2, "text", 500, 500, 50, 20, parent=0, font={"size": 16.0})]
    # clone missing the text node entirely
    partial = [_n(0, 1, "box", 0, 0, 50, 50)]
    r = sd.diff(_sk(base), _sk(partial), GATES)
    assert r["pass"] is False
    assert 1 in r["unmatched_src_high_conf"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: FAIL — `diff` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _spearman_ok(pairs, thresh):
    # rank correlation of z order across matched pairs; trivially 1.0 if <2
    if len(pairs) < 2:
        return True, 1.0
    s_rank = {id(s): i for i, (s, _) in enumerate(sorted(pairs, key=lambda p: p[0].get("z", 0)))}
    c_order = sorted(pairs, key=lambda p: p[1].get("z", 0))
    concord = sum(1 for i, (s, _) in enumerate(c_order) if s_rank[id(s)] == i)
    corr = concord / len(pairs)
    return corr >= thresh, corr


def diff(src, clone, gates):
    matches, un_src, un_clone = align(src["nodes"], clone["nodes"])
    per, fails = [], []
    min_iou, max_pos, max_size = 1.0, 0.0, 0.0
    for s, c in matches:
        d = node_delta(s, c)
        per.append({"src": s["id"], "clone": c["id"], **d})
        min_iou = min(min_iou, d["iou"])
        max_pos = max(max_pos, d["pos_err"])
        max_size = max(max_size, d["w_err"], d["h_err"])
        if d["iou"] < gates["iou"]:
            fails.append((s["id"], "iou", d["iou"]))
        if d["pos_err"] > gates["pos"]:
            fails.append((s["id"], "pos", d["pos_err"]))
        if max(d["w_err"], d["h_err"]) > gates["size"]:
            fails.append((s["id"], "size", max(d["w_err"], d["h_err"])))
        if not d["role_ok"]:
            fails.append((s["id"], "role", c["role"]))
        if not d["font_size_ok"]:
            fails.append((s["id"], "font_size", c.get("font", {}).get("size")))
        if not d["sizing_w_ok"]:
            fails.append((s["id"], "sizing_w", c.get("sizing", {}).get("w")))
        if not d["sizing_h_ok"]:
            fails.append((s["id"], "sizing_h", c.get("sizing", {}).get("h")))
    total = len(src["nodes"]) or 1
    matched_frac = len(matches) / total
    hi_un = [n["id"] for n in un_src if n.get("confidence") != "low"]
    zrank_ok, zrank = _spearman_ok(matches, gates["zrank"])
    tree = tree_agreement(matches)
    tree_ok = tree >= gates["tree"]
    ok = (not fails and matched_frac >= gates["matched_frac"]
          and not hi_un and zrank_ok and tree_ok)
    return {"pass": ok, "matched": len(matches), "matched_frac": matched_frac,
            "unmatched_src_high_conf": hi_un, "unmatched_clone": len(un_clone),
            "failures": fails, "per_node": per,
            "measured": {"min_iou": min_iou, "max_pos_err": max_pos,
                         "max_size_err": max_size, "zrank": zrank, "tree": tree}}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_skeleton_diff.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/skeleton_diff.py scripts/test_skeleton_diff.py
git commit -m "feat: add skeleton_diff gates with sizing tree zrank and measured-floor report"
```

### Task C5: `main()` CLI + live self-diff sanity (calibration)

**Files:**
- Modify: `$SCR/skeleton_diff.py`

- [ ] **Step 1: Add the CLI**

```python
import argparse
import json
from _common import emit_json

DEFAULT_GATES = {"iou": 0.98, "pos": 1.0, "size": 1.0, "matched_frac": 0.99,
                 "zrank": 0.99, "tree": 0.99}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("source")
    p.add_argument("clone")
    p.add_argument("--iou", type=float, default=DEFAULT_GATES["iou"])
    p.add_argument("--pos", type=float, default=DEFAULT_GATES["pos"])
    p.add_argument("--size", type=float, default=DEFAULT_GATES["size"])
    p.add_argument("--matched-frac", type=float, default=DEFAULT_GATES["matched_frac"], dest="mf")
    p.add_argument("--tree", type=float, default=DEFAULT_GATES["tree"])
    args = p.parse_args()
    gates = {"iou": args.iou, "pos": args.pos, "size": args.size,
             "matched_frac": args.mf, "zrank": DEFAULT_GATES["zrank"],
             "tree": args.tree}
    src = json.load(open(args.source))
    clone = json.load(open(args.clone))
    emit_json(diff(src, clone, gates))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Live self-diff calibration (kasane↔kasane must pass ~perfectly)**

Run: `cd $SCR && python3 skeleton_diff.py /tmp/kasane.json /tmp/kasane.json`
Expected: `{"pass": true, "matched_frac": 1.0, "measured": {"min_iou": 1.0, "max_pos_err": 0.0, "tree": 1.0, ...}}`. If not 1.0, `align` is mismatching identical nodes — fix before using as a cert. This is the measured floor (spec §6 calibration): the consuming crate plan ratchets its build gates to `99th-pct observed delta + epsilon` against this floor.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/skeleton_diff.py
git commit -m "feat: add skeleton_diff CLI and self-diff calibration sanity"
```

### Phase C acceptance
`skeleton_diff.py` exists; 7 pure tests pass; kasane self-diff returns `pass:true, min_iou 1.0, tree 1.0`.

---

## Phase D — bundle writer

Assemble the spec §5 `bundle/` directory from the Phase-A skeleton, Phase-B tokens, the wildwood §3 motion table (kasane-specific, baked literal), and node-role-derived asset slots. Pure assembly funcs are unit-tested; `main()` writes the files.

### Task D1: `KASANE_MOTION` literal + `match_motion` — map §3 rows to node ids by bbox anchor

**Files:**
- Create: `$SCR/bundle_writer.py`
- Test: `$SCR/test_bundle_writer.py`

The wildwood §3 anchors (absolute scrollY / REST page-y): hero img 1774, hero h1 2183, Trail h2 14484, scale panels 17297, Process h2 18467, Seasons h2 21829, mid split-block 27738–27946, Dialogue 32072–34244. Each §3 motion row is keyed to a y-anchor band; `match_motion` assigns `anim_ref` + a motion row to the nearest in-band node.

- [ ] **Step 1: Write the failing test**

```python
# test_bundle_writer.py
import bundle_writer as bw

def test_kasane_motion_rows_have_required_fields():
    for row in bw.KASANE_MOTION:
        for k in ("name", "anchor", "easing", "cubic_bezier", "amplitude",
                  "axis", "window", "klass", "source", "rms"):
            assert k in row, f"{row.get('name')} missing {k}"
        assert isinstance(row["cubic_bezier"], list) and len(row["cubic_bezier"]) == 4
        assert row["klass"] in ("scroll", "time")
        assert row["source"] in ("web_anim", "flipbook")

def test_match_motion_assigns_nearest_in_band():
    nodes = [
        {"id": 0, "role": "image", "bbox": {"x": 0, "y": 1774, "w": 600, "h": 96}, "anim_ref": None},
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 2183, "w": 600, "h": 96}, "anim_ref": None},
        {"id": 2, "role": "box", "bbox": {"x": 0, "y": 9000, "w": 10, "h": 10}, "anim_ref": None},
    ]
    rows = bw.match_motion(nodes, bw.KASANE_MOTION, band=400.0)
    # hero img node gets a motion row; the y=9000 node (no anchor nearby) gets none
    by_id = {r["node_id"]: r for r in rows}
    assert 0 in by_id            # hero image matched
    assert 2 not in by_id        # no in-band §3 anchor near y=9000
    # the matched node's anim_ref is set on the node in place
    assert nodes[0]["anim_ref"] is not None
    assert nodes[2]["anim_ref"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -v`
Expected: FAIL — module/`KASANE_MOTION`/`match_motion` not defined

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""bundle_writer — assemble the spec §5 portable bundle/ directory from a
web_skeleton skeleton + web_tokens tokens + the wildwood §3 certified motion
table (kasane) + node-role-derived asset slots. Pure assembly funcs are
unit-tested; main() writes the files."""
from __future__ import annotations
import json
from pathlib import Path

# Wildwood §3 CERTIFIED ANIMATION TABLE, transcribed verbatim (the kasane motion
# source). Generic captures read motion from a web_anim/flipbook pass instead.
# anchor = REST page-y of the animated node (the §3 absolute-scrollY anchors).
# window = [start, end] absolute scrollY px; amplitude in CSS px; axis the moved
# channel; klass scroll|time; cubic_bezier the easing control points.
KASANE_MOTION = [
    {"name": "hero_split_left", "anchor": 2183, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -720, "axis": "tx",
     "window": [0, 1219], "klass": "scroll", "source": "web_anim", "rms": 0.016},
    {"name": "hero_split_right", "anchor": 2183, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": 720, "axis": "tx",
     "window": [0, 1219], "klass": "scroll", "source": "web_anim", "rms": 0.016},
    {"name": "hero_bg_parallax", "anchor": 1774, "easing": "ease-out",
     "cubic_bezier": [0, 0, 0.58, 1], "amplitude": -218.5, "axis": "ty",
     "window": [0, 1219], "klass": "scroll", "source": "web_anim", "rms": 0.016},
    {"name": "scroll_indicator", "anchor": 1774, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": -88.7, "axis": "ty",
     "window": [0, 1219], "klass": "scroll", "source": "web_anim", "rms": 0.020},
    {"name": "intro_lede", "anchor": 2183, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": 24, "axis": "ty",
     "window": [871, 1161], "klass": "scroll", "source": "web_anim", "rms": 0.033},
    {"name": "intro_body", "anchor": 2183, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": 38.5, "axis": "ty",
     "window": [871, 1277], "klass": "scroll", "source": "web_anim", "rms": 0.044},
    {"name": "scale_panel_trail", "anchor": 14484, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 5, "axis": "scale",
     "window": [13600, 16300], "klass": "scroll", "source": "web_anim", "rms": 0.055},
    {"name": "mid_grid_scale", "anchor": 17297, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 5, "axis": "scale",
     "window": [16210, 17102], "klass": "scroll", "source": "web_anim", "rms": 0.011},
    {"name": "process_reveal", "anchor": 18467, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": 38.5, "axis": "ty",
     "window": [18000, 18600], "klass": "scroll", "source": "web_anim", "rms": 0.044},
    {"name": "seasons_marquee", "anchor": 21829, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 1100, "axis": "tx",
     "window": [0, 0], "klass": "time", "source": "flipbook", "rms": 0.0},
    {"name": "mid_paragraph_fade", "anchor": 27738, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 1, "axis": "op",
     "window": [0, 0], "klass": "time", "source": "flipbook", "rms": 0.0},
    {"name": "dialogue_bg_parallax", "anchor": 32072, "easing": "linear",
     "cubic_bezier": [0, 0, 1, 1], "amplitude": 443.5, "axis": "ty",
     "window": [32057, 32997], "klass": "scroll", "source": "web_anim", "rms": 0.018},
    {"name": "dialogue_split_lines", "anchor": 33206, "easing": "easeOutCubic",
     "cubic_bezier": [0.33, 1, 0.68, 1], "amplitude": 50.5, "axis": "ty",
     "window": [33206, 34041], "klass": "scroll", "source": "web_anim", "rms": 0.011},
]


def match_motion(nodes, motion_rows, band=400.0):
    """Assign each motion row to the nearest node within `band` px of its anchor
    (REST page-y). Sets node['anim_ref'] in place. Returns the motion.json rows:
    [{node_id, name, easing, cubic_bezier, amplitude, axis, window, class,
      source, rms}, ...]."""
    out = []
    for row in motion_rows:
        anchor = row["anchor"]
        best, best_d = None, None
        for n in nodes:
            d = abs(n["bbox"]["y"] - anchor)
            if d <= band and (best_d is None or d < best_d):
                best, best_d = n, d
        if best is None:
            continue
        best["anim_ref"] = row["name"]
        out.append({
            "node_id": best["id"], "name": row["name"], "easing": row["easing"],
            "cubic_bezier": row["cubic_bezier"], "amplitude": row["amplitude"],
            "axis": row["axis"], "window": row["window"], "class": row["klass"],
            "source": row["source"], "rms": row["rms"],
        })
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: add bundle_writer kasane motion table and bbox-anchor motion matcher"
```

### Task D2: `derive_slots` — asset manifest slots from node roles (spec §5.3)

**Files:**
- Modify: `$SCR/bundle_writer.py`
- Test: `$SCR/test_bundle_writer.py`

Slot derivation (spec §5.3): one slot per swappable node — `image` {bbox, aspect, sizing}; `text` {bbox, font, sizing, suggested_max_glyphs}; `svg` {bbox, aspect, vec_ref (null until web_vectors runs)}. `box`/`unknown_box` are structural, not swappable → no slot.

- [ ] **Step 1: Write the failing test**

```python
def test_derive_slots_per_role():
    nodes = [
        {"id": 0, "role": "image", "bbox": {"x": 0, "y": 0, "w": 200, "h": 100},
         "sizing": {"w": "fill", "h": "fixed", "confidence": "high"}},
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
         "sizing": {"w": "hug", "h": "hug", "confidence": "high"},
         "font": {"size": 16.0, "weight": 400}, "text_len": 18},
        {"id": 2, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 50, "h": 50},
         "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"}},
        {"id": 3, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
         "sizing": {"w": "fill", "h": "hug", "confidence": "high"}},
    ]
    slots = bw.derive_slots(nodes)
    by_id = {s["node_id"]: s for s in slots}
    assert set(by_id) == {0, 1, 2}              # box (id 3) is structural, no slot
    assert by_id[0]["kind"] == "image"
    assert by_id[0]["aspect"] == 2.0            # 200/100
    assert by_id[0]["sizing"] == nodes[0]["sizing"]
    assert by_id[1]["kind"] == "text"
    assert by_id[1]["font"]["size"] == 16.0
    assert by_id[1]["suggested_max_glyphs"] == 27   # text_len 18 * 1.5
    assert by_id[2]["kind"] == "svg"
    assert by_id[2]["aspect"] == 1.0
    assert by_id[2]["vec_ref"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py::test_derive_slots_per_role -v`
Expected: FAIL — `derive_slots` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _aspect(b):
    return round(b["w"] / b["h"], 4) if b["h"] else None


def derive_slots(nodes):
    """spec §5.3 asset slots, one per swappable node (image/text/svg).
    box/unknown_box are structural and get no slot."""
    slots = []
    for n in nodes:
        role = n["role"]
        b = n["bbox"]
        if role == "image":
            slots.append({"node_id": n["id"], "kind": "image",
                          "bbox": b, "aspect": _aspect(b),
                          "sizing": n.get("sizing")})
        elif role == "text":
            tl = n.get("text_len") or 0
            slots.append({"node_id": n["id"], "kind": "text",
                          "bbox": b, "font": n.get("font"),
                          "sizing": n.get("sizing"),
                          "suggested_max_glyphs": int(round(tl * 1.5))})
        elif role == "svg":
            slots.append({"node_id": n["id"], "kind": "svg",
                          "bbox": b, "aspect": _aspect(b), "vec_ref": None})
    return slots
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: add bundle_writer asset-slot derivation from node roles"
```

### Task D3: `apply_token_refs` — map node colors to tokens.json roles (spec §5.1 token_ref)

**Files:**
- Modify: `$SCR/bundle_writer.py`
- Test: `$SCR/test_bundle_writer.py`

`web_skeleton` emits `token_ref: {bg:null, fg:null, border:null}` placeholders. The bundle writer (which has both skeleton and tokens) resolves each node's captured colors to the nearest semantic role name from `tokens.json`. The node's per-color values come from the `_node_colors` sidecar `web_skeleton` wrote into `skeleton.json` (keyed by node id) — NO second live pass. This makes the bundle reproducible from `skeleton.json` + `tokens.json` alone.

- [ ] **Step 1: Write the failing test**

```python
def test_apply_token_refs_maps_nearest_role():
    palette = {"background": "#0b0b0c", "surface": "#15151a",
               "fg-primary": "#f5f5f0", "fg-muted": "#9a9a93",
               "accent": "#c8552a", "border": "#2a2a30"}
    nodes = [{"id": 0, "role": "text",
              "token_ref": {"bg": None, "fg": None, "border": None}}]
    node_colors = {0: {"bg": "rgb(21,21,26)", "fg": "rgb(245,245,240)",
                       "border": "rgb(42,42,48)"}}
    bw.apply_token_refs(nodes, palette, node_colors)
    tr = nodes[0]["token_ref"]
    assert tr["bg"] == "surface"       # #15151a
    assert tr["fg"] == "fg-primary"    # #f5f5f0
    assert tr["border"] == "border"    # #2a2a30

def test_apply_token_refs_leaves_none_for_transparent():
    palette = {"background": "#0b0b0c"}
    nodes = [{"id": 0, "role": "box", "token_ref": {"bg": None, "fg": None, "border": None}}]
    node_colors = {0: {"bg": "rgba(0,0,0,0)", "fg": None, "border": None}}
    bw.apply_token_refs(nodes, palette, node_colors)
    assert nodes[0]["token_ref"]["bg"] is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py::test_apply_token_refs_maps_nearest_role test_bundle_writer.py::test_apply_token_refs_leaves_none_for_transparent -v`
Expected: FAIL — `apply_token_refs` not defined

- [ ] **Step 3: Write minimal implementation**

```python
import web_tokens as wt


def _nearest_role(css, palette):
    """Nearest semantic role name to a css color, or None if transparent / no
    palette entry within a sane distance."""
    rgb = wt.parse_color(css)
    if rgb is None:
        return None
    best, best_d = None, None
    for name, hexval in palette.items():
        prgb = wt.parse_color(hexval)
        if prgb is None:
            continue
        d = sum((a - b) ** 2 for a, b in zip(rgb, prgb)) ** 0.5
        if best_d is None or d < best_d:
            best, best_d = name, d
    return best


def apply_token_refs(nodes, palette, node_colors):
    """Resolve each node's captured bg/fg/border colors to the nearest tokens.json
    semantic role name. node_colors: {node_id: {bg, fg, border}} raw css."""
    for n in nodes:
        cols = node_colors.get(n["id"], {})
        n["token_ref"] = {
            "bg": _nearest_role(cols.get("bg"), palette),
            "fg": _nearest_role(cols.get("fg"), palette),
            "border": _nearest_role(cols.get("border"), palette),
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: add bundle_writer token_ref resolution to nearest semantic role"
```

### Task D4: `assemble` + `write_bundle` + `main()` — emit the bundle directory (spec §5)

**Files:**
- Modify: `$SCR/bundle_writer.py`
- Test: `$SCR/test_bundle_writer.py`

- [ ] **Step 1: Write the failing test** (pure `assemble` returns the in-memory bundle dict; `write_bundle` is exercised against tmp_path)

```python
def test_assemble_builds_all_five_documents():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 1440, "h": 887, "dpr": 2},
                "page": {"w": 1440, "h": 35137},
                "nodes": [
                    {"id": 0, "role": "image", "bbox": {"x": 0, "y": 1774, "w": 600, "h": 96},
                     "sizing": {"w": "fill", "h": "fixed", "confidence": "high"},
                     "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None},
                ]}
    tokens = {"palette": {"background": "#0b0b0c"}, "type_scale": [16, 64]}
    node_colors = {0: {"bg": "rgb(11,11,12)", "fg": None, "border": None}}
    bundle = bw.assemble(skeleton, tokens, node_colors, bw.KASANE_MOTION,
                         meta_extra={"timestamp": "2026-05-28T00:00:00Z"})
    assert set(bundle.keys()) == {"meta", "skeleton", "tokens", "motion", "manifest"}
    assert bundle["meta"]["url"] == "u"
    assert bundle["meta"]["viewport"] == {"w": 1440, "h": 887, "dpr": 2}
    assert bundle["meta"]["page"] == {"w": 1440, "h": 35137}
    # motion: hero image (y=1774) matched
    assert any(r["node_id"] == 0 for r in bundle["motion"])
    assert bundle["skeleton"]["nodes"][0]["anim_ref"] == "hero_bg_parallax"
    # token_ref resolved
    assert bundle["skeleton"]["nodes"][0]["token_ref"]["bg"] == "background"
    # manifest slot for the image
    assert any(s["node_id"] == 0 and s["kind"] == "image" for s in bundle["manifest"]["slots"])

def test_write_bundle_creates_files(tmp_path):
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 1, "h": 1, "dpr": 1}, "page": {"w": 1, "h": 1},
                "nodes": []}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    bw.write_bundle(bundle, str(tmp_path))
    import os
    for f in ["meta.json", "skeleton.json", "tokens.json", "motion.json"]:
        assert os.path.exists(os.path.join(str(tmp_path), f))
    assert os.path.exists(os.path.join(str(tmp_path), "assets", "manifest.json"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py::test_assemble_builds_all_five_documents test_bundle_writer.py::test_write_bundle_creates_files -v`
Expected: FAIL — `assemble` / `write_bundle` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra):
    """Build the in-memory bundle: meta + skeleton (with anim_ref/token_ref
    filled) + tokens + motion + assets/manifest. Mutates skeleton nodes in place
    to set anim_ref and token_ref."""
    nodes = skeleton["nodes"]
    palette = tokens.get("palette", {})
    apply_token_refs(nodes, palette, node_colors)
    motion = match_motion(nodes, motion_rows)
    slots = derive_slots(nodes)
    meta = {
        "url": skeleton.get("url"),
        "viewport": skeleton.get("viewport"),
        "page": skeleton.get("page"),
        "dpr": skeleton.get("viewport", {}).get("dpr"),
        "schema": skeleton.get("schema"),
    }
    meta.update(meta_extra or {})
    return {
        "meta": meta,
        "skeleton": skeleton,
        "tokens": tokens,
        "motion": motion,
        "manifest": {"slots": slots},
    }


def write_bundle(bundle, out_dir):
    """Write the bundle to the spec §5 directory layout."""
    root = Path(out_dir)
    (root / "assets").mkdir(parents=True, exist_ok=True)
    (root / "meta.json").write_text(json.dumps(bundle["meta"], indent=2))
    (root / "skeleton.json").write_text(json.dumps(bundle["skeleton"], indent=2))
    (root / "tokens.json").write_text(json.dumps(bundle["tokens"], indent=2))
    (root / "motion.json").write_text(json.dumps(bundle["motion"], indent=2))
    (root / "assets" / "manifest.json").write_text(
        json.dumps(bundle["manifest"], indent=2))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (7 tests)

- [ ] **Step 5: Add the `main()` CLI** (no unit test — pure offline assembly from on-disk skeleton + tokens; no transport, no live pass)

```python
import argparse
import time
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--skeleton", required=True, help="skeleton.json from web_skeleton")
    p.add_argument("--tokens", required=True, help="tokens.json from web_tokens")
    p.add_argument("--out", required=True, help="bundle/ output directory")
    p.add_argument("--kasane-motion", action="store_true",
                   help="pre-populate motion.json from the wildwood §3 table")
    args = p.parse_args()

    skeleton = json.loads(Path(args.skeleton).read_text())
    tokens = json.loads(Path(args.tokens).read_text())

    # node_colors comes from the skeleton's _node_colors sidecar (string keys in
    # JSON -> int node ids). Empty dict if absent (token_ref stays null).
    raw_colors = skeleton.pop("_node_colors", {})
    node_colors = {int(k): v for k, v in raw_colors.items()}

    motion_rows = KASANE_MOTION if args.kasane_motion else []
    bundle = assemble(skeleton, tokens, node_colors, motion_rows,
                      meta_extra={"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                             time.gmtime())})
    write_bundle(bundle, args.out)
    emit_json({"ok": True, "out": args.out, "nodes": len(skeleton["nodes"]),
               "motion_rows": len(bundle["motion"]),
               "slots": len(bundle["manifest"]["slots"])})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

(`skeleton.pop("_node_colors", ...)` strips the internal sidecar so it does not ship in the bundle's `skeleton.json` — the crate never sees it.)

- [ ] **Step 6: Build the kasane bundle**

Run: `cd $SCR && python3 bundle_writer.py --skeleton /tmp/kasane.json --tokens /tmp/kasane_tokens.json --out /tmp/kasane_bundle --kasane-motion`
Expected: `{"ok": true, "out": "/tmp/kasane_bundle", "nodes": <hundreds>, "motion_rows": <up to 13>, "slots": <many>}`; `/tmp/kasane_bundle/` contains `meta.json skeleton.json tokens.json motion.json assets/manifest.json`. Confirm `motion.json` has the hero rows, `skeleton.json`'s hero image node has `anim_ref:"hero_bg_parallax"`, that hero/text nodes have non-null `token_ref` roles, and that the shipped `skeleton.json` has NO `_node_colors` key.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: add bundle_writer assemble write_bundle and CLI emitting the portable bundle"
```

### Phase D acceptance
`bundle_writer.py` exists; 7 pure tests pass; live `/tmp/kasane_bundle/` contains all five documents with the §3 motion rows mapped onto the hero nodes and asset slots derived per role.

---

## Phase E — `web_vectors` (TAIL — lowest priority)

Opt-in vtracer raster→SVG **reference** traces (non-certified, IP-clean) for `role:svg` nodes. The slots themselves already come free from the skeleton (Phase D `derive_slots` emits `vec_ref:null`); this verb only fills `vec/<id>.svg` and flips the slot's `vec_ref`. **Verify vtracer is installable before building.**

### Task E1: Verify `vtracer` availability + `crop_rect` for an svg node

**Files:**
- Create: `$SCR/web_vectors.py`
- Test: `$SCR/test_web_vectors.py`

- [ ] **Step 1: Verify vtracer exists** (prerequisite gate — do NOT build the verb if this fails)

Run: `cargo install vtracer --dry-run 2>&1 | head -5 || vtracer --help 2>&1 | head -3`
Expected: vtracer is resolvable on crates.io OR already on PATH. If neither, STOP this phase and note in SKILL.md honest-limits that `web_vectors` is deferred (slots still ship from the skeleton with `vec_ref:null`). Document the decision; do not write dead code.

- [ ] **Step 2: Write the failing test**

```python
# test_web_vectors.py
import web_vectors as wv

def test_crop_rect_scales_by_dpr():
    # node bbox in CSS px; screenshot is dpr-scaled device px
    node = {"id": 7, "role": "svg", "bbox": {"x": 100, "y": 200, "w": 50, "h": 40}}
    rect = wv.crop_rect(node, dpr=2.0)
    assert rect == {"left": 200, "top": 400, "width": 100, "height": 80}

def test_svg_nodes_filters_role():
    nodes = [{"id": 0, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}},
             {"id": 1, "role": "image", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}},
             {"id": 2, "role": "svg", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}}]
    assert [n["id"] for n in wv.svg_nodes(nodes)] == [0, 2]
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_vectors.py -v`
Expected: FAIL — module/functions not defined

- [ ] **Step 4: Write minimal implementation**

```python
#!/usr/bin/env python3
"""web_vectors — OPT-IN vtracer raster->SVG REFERENCE traces (non-certified,
IP-clean) for role:svg nodes. Slots ship from the skeleton already; this verb
only fills vec/<id>.svg + flips the slot vec_ref. Pure crop/filter funcs are
unit-tested; the vtracer subprocess in main() is live-validated."""
from __future__ import annotations


def crop_rect(node, dpr):
    """Convert a node's CSS-px bbox to device-px crop rect for a dpr screenshot."""
    b = node["bbox"]
    return {"left": int(round(b["x"] * dpr)), "top": int(round(b["y"] * dpr)),
            "width": int(round(b["w"] * dpr)), "height": int(round(b["h"] * dpr))}


def svg_nodes(nodes):
    return [n for n in nodes if n.get("role") == "svg"]
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_vectors.py -v`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_vectors.py scripts/test_web_vectors.py
git commit -m "feat: add web_vectors crop-rect and svg-node filter"
```

### Task E2: `main()` — screenshot crop → vtracer → vec/<id>.svg (I/O, live-validated)

**Files:**
- Modify: `$SCR/web_vectors.py`

- [ ] **Step 1: Write the I/O wiring** (no unit test — live-validated; reuses the existing `web_shot` capability via the shared transport)

```python
import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args


def _vtracer(in_png, out_svg):
    """Run vtracer raster->svg; returns True on success."""
    try:
        subprocess.run(["vtracer", "--input", in_png, "--output", out_svg],
                       check=True, capture_output=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--skeleton", required=True, help="skeleton.json (for svg nodes)")
    p.add_argument("--bundle", required=True, help="bundle dir to write vec/ + update manifest")
    add_transport_args(p)
    args = p.parse_args()

    skeleton = json.loads(Path(args.skeleton).read_text())
    targets = svg_nodes(skeleton["nodes"])
    if not targets:
        emit_json({"ok": True, "traced": 0, "note": "no svg nodes"})
        return 0

    engine, ev, device = resolve_web_eval(args)
    if not hasattr(ev, "sess"):
        die("web_vectors needs a CDP transport for clipped screenshots.")
    navigate(ev, engine, args.url)
    dpr = ev.ev("devicePixelRatio")

    vec_dir = Path(args.bundle) / "assets" / "vec"
    vec_dir.mkdir(parents=True, exist_ok=True)
    traced = []
    for n in targets:
        rect = crop_rect(n, dpr)
        shot = ev.sess.send("Page.captureScreenshot", {
            "format": "png", "clip": {"x": rect["left"] / dpr, "y": rect["top"] / dpr,
            "width": rect["width"] / dpr, "height": rect["height"] / dpr, "scale": 1}})
        import base64
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp.write(base64.b64decode(shot["data"]))
            png_path = tmp.name
        svg_path = str(vec_dir / f"{n['id']}.svg")
        if _vtracer(png_path, svg_path):
            traced.append(n["id"])
    ev.close()

    # flip vec_ref on the matching manifest slots
    man_path = Path(args.bundle) / "assets" / "manifest.json"
    if man_path.exists():
        man = json.loads(man_path.read_text())
        for s in man.get("slots", []):
            if s.get("kind") == "svg" and s["node_id"] in traced:
                s["vec_ref"] = f"vec/{s['node_id']}.svg"
        man_path.write_text(json.dumps(man, indent=2))

    emit_json({"ok": True, "traced": len(traced), "ids": traced})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Live trace sanity (only if vtracer verified in E1 step 1)**

Run: `cd $SCR && python3 web_vectors.py --url "https://kasane-keyboard.com/craftanddesign" --skeleton /tmp/kasane.json --bundle /tmp/kasane_bundle`
Expected: `{"ok": true, "traced": <n>, "ids": [...]}`; `/tmp/kasane_bundle/assets/vec/<id>.svg` files exist; the matching svg slots in `manifest.json` now have `vec_ref:"vec/<id>.svg"`. These traces are reference-only (spec §8 — never certified, not the source art).

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_vectors.py
git commit -m "feat: add web_vectors main clipped-screenshot vtracer reference traces"
```

### Phase E acceptance
`web_vectors.py` exists; 2 pure tests pass; vtracer availability is verified (or the verb is documented-deferred); live trace fills `vec/<id>.svg` + flips `vec_ref` on svg slots.

---

## Phase F — multi-breakpoint (TAIL)

`--viewports 390,768,1440` re-runs `web_skeleton` capture under each existing `web_emu` device profile → one skeleton per breakpoint + a cross-breakpoint sizing inference pass (spec §5.1: a box that grows with the viewport = `fill`; constant = `fixed`, flagged `confidence:low`). Reuses `web_emu` device emulation — no new resizer.

### Task F1: `infer_sizing_from_breakpoints` — cross-breakpoint bbox-delta → sizing

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

```python
def test_infer_sizing_from_breakpoints():
    # one node observed at two viewport widths
    # node A: width grows with viewport (390->1440) -> fill (low confidence)
    # node B: width constant -> fixed (low confidence)
    obs = {
        "A": [{"vw": 390, "w": 390, "h": 100}, {"vw": 1440, "w": 1440, "h": 100}],
        "B": [{"vw": 390, "w": 200, "h": 50}, {"vw": 1440, "w": 200, "h": 50}],
    }
    a = ws.infer_sizing_from_breakpoints(obs["A"])
    b = ws.infer_sizing_from_breakpoints(obs["B"])
    assert a == {"w": "fill", "h": "fixed", "confidence": "low"}
    assert b == {"w": "fixed", "h": "fixed", "confidence": "low"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_infer_sizing_from_breakpoints -v`
Expected: FAIL — `infer_sizing_from_breakpoints` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def infer_sizing_from_breakpoints(observations, grow_eps=2.0):
    """spec §5.1: infer sizing from multi-breakpoint bbox-deltas when no DOM
    sizing is available. A dimension that grows with the viewport = fill;
    constant = fixed. Always confidence:low (inferred, not read from CSS).
    observations: [{vw, w, h}, ...] sorted-agnostic; needs >=2 entries."""
    if len(observations) < 2:
        return {"w": "fixed", "h": "fixed", "confidence": "low"}
    obs = sorted(observations, key=lambda o: o["vw"])
    lo, hi = obs[0], obs[-1]

    def axis(dim):
        return "fill" if (hi[dim] - lo[dim]) > grow_eps else "fixed"

    return {"w": axis("w"), "h": axis("h"), "confidence": "low"}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (10 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton cross-breakpoint sizing inference"
```

### Task F2: `merge_breakpoints` — match nodes across skeletons by center + apply inferred sizing

**Files:**
- Modify: `$SCR/web_skeleton.py`
- Test: `$SCR/test_web_skeleton.py`

Cross-breakpoint nodes are matched by the same nearest-center heuristic the diff uses, but we keep it local to avoid a cross-module import. Inferred sizing is applied ONLY to nodes whose DOM-derived sizing is low-confidence (spec §8: DOM reads win; inference fills the gaps).

- [ ] **Step 1: Write the failing test**

```python
def test_merge_breakpoints_fills_low_confidence_only():
    # reference skeleton (the §3 viewport) has one node with low-conf sizing and
    # one with high-conf sizing
    ref = {"viewport": {"w": 1440, "h": 887, "dpr": 2}, "page": {"w": 1440, "h": 1000},
           "nodes": [
               {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 1440, "h": 100},
                "sizing": {"w": "hug", "h": "fixed", "confidence": "low"}},
               {"id": 1, "role": "box", "bbox": {"x": 0, "y": 200, "w": 200, "h": 50},
                "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"}},
           ]}
    # narrow capture: node 0's width shrank with viewport -> infer fill;
    # node 1 stayed 200 -> infer fixed (but high-conf node is untouched)
    narrow = {"viewport": {"w": 390, "h": 887, "dpr": 2},
              "nodes": [
                  {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 390, "h": 100}},
                  {"id": 1, "role": "box", "bbox": {"x": 0, "y": 200, "w": 200, "h": 50}},
              ]}
    merged = ws.merge_breakpoints(ref, [narrow], radius=40)
    n0 = next(n for n in merged["nodes"] if n["id"] == 0)
    n1 = next(n for n in merged["nodes"] if n["id"] == 1)
    assert n0["sizing"] == {"w": "fill", "h": "fixed", "confidence": "low"}  # overwritten
    assert n1["sizing"] == {"w": "fixed", "h": "fixed", "confidence": "high"}  # preserved
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py::test_merge_breakpoints_fills_low_confidence_only -v`
Expected: FAIL — `merge_breakpoints` not defined

- [ ] **Step 3: Write minimal implementation**

```python
def _center_xy(b):
    return (b["x"] + b["w"] / 2, b["y"] + b["h"] / 2)


def merge_breakpoints(ref, others, radius=40):
    """For each ref node with low-confidence DOM sizing, gather its bbox across
    the reference + other-viewport skeletons (matched by nearest center) and
    overwrite sizing with the cross-breakpoint inference. High-confidence DOM
    sizing is preserved (spec §8: DOM reads win)."""
    ref_vw = ref["viewport"]["w"]
    for n in ref["nodes"]:
        if n.get("sizing", {}).get("confidence") != "low":
            continue
        obs = [{"vw": ref_vw, "w": n["bbox"]["w"], "h": n["bbox"]["h"]}]
        cn = _center_xy(n["bbox"])
        for o in others:
            ovw = o["viewport"]["w"]
            best, best_d = None, None
            for m in o["nodes"]:
                mc = _center_xy(m["bbox"])
                d = ((cn[0] - mc[0]) ** 2 + (cn[1] - mc[1]) ** 2) ** 0.5
                if d <= radius and (best_d is None or d < best_d):
                    best, best_d = m, d
            if best is not None:
                obs.append({"vw": ovw, "w": best["bbox"]["w"], "h": best["bbox"]["h"]})
        if len(obs) >= 2:
            n["sizing"] = infer_sizing_from_breakpoints(obs)
    return ref
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add web_skeleton breakpoint merge filling low-confidence sizing"
```

### Task F3: `--viewports` in `main()` — capture per breakpoint via `web_emu` (I/O, live-validated)

**Files:**
- Modify: `$SCR/web_skeleton.py`

The transport's device emulation is the existing `web_emu` (a `--device`/`--emulate` arg surfaced by `add_transport_args` / `resolve_web_eval`). `--viewports` re-resolves the transport per width. Read the actual `web_emu` flag name from `_web_eval.py` (`add_transport_args`) before wiring — the snippet uses `args.device` as the conventional name; adjust to the real attribute.

- [ ] **Step 1: Extend `main()` to accept `--viewports`**

```python
# add to main()'s argparser (alongside --url/--out):
    p.add_argument("--viewports", default=None,
                   help="comma widths e.g. 390,768,1440; multi-breakpoint sizing inference")

# replace the single-capture body with:
    if args.viewports:
        widths = [int(w) for w in args.viewports.split(",") if w.strip()]
        # reference = the §3 viewport (widest / first), then narrower ones
        skeletons = []
        for w in sorted(widths, reverse=True):
            # re-resolve the transport under web_emu at this width.
            # NOTE: confirm the real web_emu arg name in _web_eval.add_transport_args;
            # set it on args before resolving (conventionally args.device / args.emulate).
            setattr(args, "emulate_width", w)  # placeholder attr; wire to the real web_emu flag
            engine, ev, device = resolve_web_eval(args)
            if not hasattr(ev, "sess"):
                die("web_skeleton --viewports needs a CDP transport.")
            sk, _, _ = _capture_one(ev, engine, args.url)
            ev.close()
            skeletons.append(sk)
        ref = skeletons[0]
        merged = merge_breakpoints(ref, skeletons[1:])
        out_obj = merged
    else:
        engine, ev, device = resolve_web_eval(args)
        if not hasattr(ev, "sess"):
            die("web_skeleton needs a CDP transport (chrome host / --android / --cdp-port).")
        out_obj, _, _ = _capture_one(ev, engine, args.url)
        ev.close()

    if args.out:
        Path(args.out).write_text(json.dumps(out_obj, indent=2))
        emit_json({"ok": True, "nodes": len(out_obj["nodes"]), "out": args.out,
                   "viewport": out_obj["viewport"], "page": out_obj["page"]})
    else:
        emit_json(out_obj)
    return 0
```

(Replace the old single-capture tail of `main()` from Task A7 with this branch; keep `_capture_one` as-is.)

- [ ] **Step 2: Verify on kasane at 2 widths**

First read the real web_emu flag: `grep -n "add_argument" _web_eval.py` and identify the device/emulate width arg; wire `setattr(args, ...)` to it in step 1.
Run: `cd $SCR && python3 web_skeleton.py --url "https://kasane-keyboard.com/craftanddesign" --viewports 390,1440 --out /tmp/kasane_mb.json`
Expected: `{"ok": true, ...}`; in `/tmp/kasane_mb.json` some previously-low-confidence nodes now carry inferred `fill`/`fixed` sizing (still `confidence:low`), high-confidence DOM sizing unchanged.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add scripts/web_skeleton.py
git commit -m "feat: add web_skeleton viewports multi-breakpoint capture via web_emu"
```

### Phase F acceptance
`web_skeleton --viewports` captures per breakpoint (reusing `web_emu`), merges via cross-breakpoint inference, and fills only low-confidence sizing; verified on kasane at 2 widths.

---

## Phase G — propagate to the 3 probe-runner copies

### Task G1: Propagate the new scripts wholesale

**Files:**
- Copy: `web_skeleton.py`, `test_web_skeleton.py`, `web_tokens.py`, `test_web_tokens.py`, `skeleton_diff.py`, `test_skeleton_diff.py`, `bundle_writer.py`, `test_bundle_writer.py`, `web_vectors.py`, `test_web_vectors.py` into engineering-pack + brainiac scripts dirs (scripts are safe to copy wholesale — the working copy is the canonical source of truth).
- Modify (targeted, NEVER wholesale): each copy's `SKILL.md`.

- [ ] **Step 1: Copy scripts**

```bash
SRC=~/Developer/artificial_intelligence/skills/probe-runner/scripts
for D in ~/Developer/poc-repositories/engineering-pack/.claude/skills/probe-runner ~/Developer/poc-repositories/brainiac/.claude/skills/probe-runner; do
  for F in web_skeleton.py test_web_skeleton.py web_tokens.py test_web_tokens.py skeleton_diff.py test_skeleton_diff.py bundle_writer.py test_bundle_writer.py web_vectors.py test_web_vectors.py; do
    cp "$SRC/$F" "$D/scripts/"
  done
done
```

- [ ] **Step 2: Verify tests pass from each copy**

```bash
for D in ~/Developer/artificial_intelligence/skills/probe-runner ~/Developer/poc-repositories/engineering-pack/.claude/skills/probe-runner ~/Developer/poc-repositories/brainiac/.claude/skills/probe-runner; do
  (cd "$D/scripts" && python3 -m pytest test_web_skeleton.py test_web_tokens.py test_skeleton_diff.py test_bundle_writer.py test_web_vectors.py -q)
done
```
Expected: all green in all three.

- [ ] **Step 3: Targeted SKILL.md edit** — in each copy's `SKILL.md`, add `web_skeleton`, `web_tokens`, `skeleton_diff`, `bundle_writer`, `web_vectors` to the web-verb list with a one-paragraph description (DOMSnapshot capture → content-free skeleton with sizing/layout/parent; web_tokens → semantic palette; skeleton_diff → tight geometry+sizing+tree cert; bundle_writer → portable bundle/ any agent rebuilds + swaps content + re-skins from; web_vectors → opt-in non-certified vtracer reference traces; pairs with flipbook/web_anim for full design cert; native roadmap via idb/VM). **Read each SKILL.md's web-verb section first**, then make the minimal insertion — the three copies have diverged, so do NOT paste identical blocks blindly; match each file's surrounding wording.

- [ ] **Step 4: Commit each repo** (single-line, no author trailer; stage only probe-runner files — never `git add -A`; brainiac has pre-existing dirty `templates/dioxus_*`)

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner && git add scripts/web_skeleton.py scripts/test_web_skeleton.py scripts/web_tokens.py scripts/test_web_tokens.py scripts/skeleton_diff.py scripts/test_skeleton_diff.py scripts/bundle_writer.py scripts/test_bundle_writer.py scripts/web_vectors.py scripts/test_web_vectors.py SKILL.md && git commit -m "feat: add design-capture engine web_skeleton web_tokens skeleton_diff bundle_writer web_vectors"
cd ~/Developer/poc-repositories/engineering-pack && git add .claude/skills/probe-runner/scripts/web_skeleton.py .claude/skills/probe-runner/scripts/test_web_skeleton.py .claude/skills/probe-runner/scripts/web_tokens.py .claude/skills/probe-runner/scripts/test_web_tokens.py .claude/skills/probe-runner/scripts/skeleton_diff.py .claude/skills/probe-runner/scripts/test_skeleton_diff.py .claude/skills/probe-runner/scripts/bundle_writer.py .claude/skills/probe-runner/scripts/test_bundle_writer.py .claude/skills/probe-runner/scripts/web_vectors.py .claude/skills/probe-runner/scripts/test_web_vectors.py .claude/skills/probe-runner/SKILL.md && git commit -m "feat: add design-capture engine web_skeleton web_tokens skeleton_diff bundle_writer web_vectors"
cd ~/Developer/poc-repositories/brainiac && git add .claude/skills/probe-runner/scripts/web_skeleton.py .claude/skills/probe-runner/scripts/test_web_skeleton.py .claude/skills/probe-runner/scripts/web_tokens.py .claude/skills/probe-runner/scripts/test_web_tokens.py .claude/skills/probe-runner/scripts/skeleton_diff.py .claude/skills/probe-runner/scripts/test_skeleton_diff.py .claude/skills/probe-runner/scripts/bundle_writer.py .claude/skills/probe-runner/scripts/test_bundle_writer.py .claude/skills/probe-runner/scripts/web_vectors.py .claude/skills/probe-runner/scripts/test_web_vectors.py .claude/skills/probe-runner/SKILL.md && git commit -m "feat: add design-capture engine web_skeleton web_tokens skeleton_diff bundle_writer web_vectors"
```

### Task G2: Document the native skeleton roadmap (spec §12)

**Files:**
- Modify: the working-copy `SKILL.md` honest-limits / roadmap block (and propagate the same targeted note to the other two in the same G1 SKILL.md edit if convenient).

- [ ] **Step 1: Append the roadmap note** (targeted) — `ios_skeleton` = `idb ui describe-all` frames (already the ios_flipbook oracle) → §5 bundle; `flutter_skeleton` = VM render tree (`localToGlobal`+`devicePixelRatio`, the flutter_flipbook region read) → §5 bundle; desktop "through chrome" = `web_skeleton` over the webview CDP transport unchanged; image-only input = bounded far edge (CV+OCR+vtracer, `confidence:low`, future). All emit the same §5 bundle → `skeleton_diff` + flipbook motion-cert. NOT built; same honesty model as the flipbook (exact where an introspection oracle exists).

- [ ] **Step 2: Commit** (working copy)

```bash
cd ~/Developer/artificial_intelligence/skills/probe-runner
git add SKILL.md
git commit -m "docs: note native skeleton roadmap ios flutter desktop for design sweep"
```

### Phase G acceptance
All five new scripts + tests present and green in all 3 probe-runner copies; each `SKILL.md` updated (targeted); native roadmap documented; all repos committed single-line.

---

## Self-Review

### 1. Spec coverage

| Spec requirement | Task(s) |
|------------------|---------|
| §4 DOMSnapshot whitelist incl. sizing inputs | A1 (`WANT_STYLES` extended) |
| §4 capture-state REST protocol + verify-before-lock | A7 (`_REST_JS`) + A8 (kasane hero anchor 1774 check) |
| §4 reference viewport (887px) | A8 step 3 |
| §4 role classifier (image/svg/text/box/unknown_box fallback) | A2 |
| §4 multi-breakpoint `--viewports` (reuse web_emu) | F1–F3 |
| §5.1 skeleton schema (id/role/confidence/bbox/z/parent/font/text_len/layout/sizing/token_ref/anim_ref) | A6 locks it; parent A5; sizing A3; layout A4 |
| §5.1 content dropped (text/src) | A6 (`test_to_skeleton_drops_content`) |
| §5.1 sizing derivation (fill/hug/fixed) | A3; low-conf inference F1 |
| §5.2 tokens palette role assignment + clustering + confidence | B1 (cluster) + B2 (roles) |
| §5.2 type_scale/weights/families/spacing/radii/shadows | B3 |
| §5.3 motion.json row shape (node_id/easing/cubic_bezier/amplitude/axis/window/class/source/rms) | D1 (`match_motion` output) |
| §5.3 kasane motion pre-populated from §3 | D1 (`KASANE_MOTION` verbatim) |
| §5.3 assets/manifest slots (image/text/svg) | D2 (`derive_slots`) |
| §5 bundle directory (meta/skeleton/tokens/motion/assets/manifest) | D4 (`assemble` + `write_bundle`) |
| §5.1 token_ref → tokens.json role | D3 (`apply_token_refs`) |
| §6.2 bbox IoU/pos/size + role exact + font exact + sizing exact (high-conf) | C1 + C4 |
| §6.3 matched-frac + unmatched-high-conf + z-rank + parent-tree ≥0.99 | C4 (+ C3 tree) |
| §6 calibration to measured floor (self-diff) | C5 step 2 |
| §6.4 report (per-node deltas + measured floor) | C4 (`measured`) |
| §8 vtracer reference-only (never certified) | E (whole phase, non-certified) |
| §8 sizing inference low-confidence only | F1 (always `confidence:low`) + F2 (DOM wins) |
| §9.1 web_skeleton offline TDD + capture-state verify + live | Phase A |
| §9.2 web_tokens TDD + live | Phase B |
| §9.3 skeleton_diff TDD (identical PASS; shift/role/sizing/tree FAIL) + self-diff | C4 + C5 |
| §9.4 bundle writer (motion from §3) | Phase D |
| §9.8 web_vectors built last | Phase E (tail) |
| §9.9 multi-breakpoint | Phase F (tail) |
| §9.10 propagate (scripts wholesale, SKILL.md targeted, single-line commit) | G1 |
| §9.11 / §12 native roadmap documented | G2 |
| §10 TDD: classifier roles + unknown fallback + sizing combos + content dropped | A2 + A3 + A6 |
| §10 TDD: tokens clustering + role + low-conf | B1 + B2 |
| §10 TDD: diff identical PASS, shift/role/sizing/font/tree FAIL, unmatched-high-conf FAIL, per-gate floor | C4 |

All spec §4/§5/§6/§9/§10/§12 requirements that are engine-scoped map to a task. (Spec §7 crate, §11 acceptance criteria that depend on the crate, and §3-as-rendered are the SEPARATE crate plan — explicitly out of scope.)

### 2. Placeholder scan

- No "TBD" / "implement later" / "add error handling" / "similar to Task N" anywhere — every code step is full code.
- One intentional, flagged placeholder: F3 step 1 uses `setattr(args, "emulate_width", w)` with an inline note to wire it to the real `web_emu` arg name read from `_web_eval.add_transport_args` (verified in F3 step 2). This is unavoidable — the exact flag name is an attribute of an existing module the plan must not guess; the task instructs reading it live. Not a content gap.
- Color → `token_ref` mapping is NOT positional. `web_skeleton.to_skeleton` (A6) captures a `_node_colors` sidecar keyed by node id in the SAME pass that emits/filters nodes, and A7 serializes it into `skeleton.json`. `bundle_writer.main()` (D4) reads that sidecar by id — no second live pass, no positional alignment between `querySelectorAll('*')` and the filtered/reordered nodes list. The sidecar is `pop`-stripped before the bundle's `skeleton.json` is written so the crate never sees it. D3's pure test exercises `apply_token_refs` with an explicit id-keyed `node_colors`.

### 3. Type / name consistency

- `WANT_STYLES` — defined A1, referenced A1/A7 (capture) consistently.
- `parse_snapshot(snap, want_styles)` — A1, used A7.
- `classify(rec, in_svg)` / `svg_descendants(doc, strings)` — A2, used A6/A7.
- `derive_sizing(st, axis)` returns `(label, confidence)` — A3, used in A6.
- `derive_layout(st)` returns the 8-key dict — A4, used in A6 and asserted in A6's schema test.
- `build_parent_map(emitted, parent_index)` — A5, used in A6.
- `to_skeleton(recs, svg_set, parent_index, url, viewport, page)` returns `(skeleton, node_colors)` — A6 signature; A7 `_capture_one(ev, engine, url)` unpacks the tuple and writes `skeleton["_node_colors"]`; all three `_capture_one` call sites (A7 main, F3 both branches) pass `engine`. Both A6 tests unpack the tuple.
- `_px` defined once (A4), reused by A6's font parsing — single definition, no shadowing (A6 does not redefine `_px`).
- `iou` / `node_delta(s,c)` / `align(src,clone,radius)` / `tree_agreement(matches)` / `diff(src,clone,gates)` — C1/C2/C3/C4 consistent; `node_delta` returns `sizing_w_ok`/`sizing_h_ok`/`font_size_ok`/`role_ok` used verbatim in `diff`.
- `GATES`/`DEFAULT_GATES` include `tree` key — added C4 test + C4 impl + C5 CLI consistently.
- `KASANE_MOTION` rows use key `klass` internally (avoids the `class` keyword) and emit JSON key `"class"` in `match_motion` output — test D1 checks `row["klass"]` (literal) and the assemble test checks `r["class"]` (output) — consistent and intentional.
- `match_motion(nodes, motion_rows, band)` / `derive_slots(nodes)` / `apply_token_refs(nodes, palette, node_colors)` / `assemble(skeleton, tokens, node_colors, motion_rows, meta_extra)` / `write_bundle(bundle, out_dir)` — D1–D4 consistent; `assemble` calls all three in the right order.
- `web_tokens` funcs `parse_color` / `cluster_colors(samples, tol)` / `assign_roles(bg,fg,border)` / `build_scales(rows, shadows)` — B1–B3 consistent; `bundle_writer` imports `web_tokens as wt` and uses `wt.parse_color` (D3) — matches B1.
- `crop_rect(node, dpr)` / `svg_nodes(nodes)` — E1, used E2.
- `infer_sizing_from_breakpoints(observations)` / `merge_breakpoints(ref, others, radius)` — F1/F2; F2 calls `infer_sizing_from_breakpoints`; F3 calls `merge_breakpoints`. Consistent.

No inconsistencies found. Commits are all single-line with no `Co-Authored-By` / author trailer (per the operator git rule).
