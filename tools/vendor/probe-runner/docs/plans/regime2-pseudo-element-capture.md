# Regime-2 Pseudo-Element Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture `::before`/`::after`/`::marker` resolved box-style + a content-free `content` value as an additive per-node `pseudo` field on the originating element's skeleton node.

**Architecture:** `DOMSnapshot.captureSnapshot` already enumerates pseudo-elements as nodes (own `nodeName` `::before`/`::after`/`::marker`, a `pseudoType`, a parallel `layout.styles` row, and `parentIndex` → originating element). So this is a Regime-1-style extension, not a new pass: append `content` to the computed-style whitelist, stop emitting pseudo records as standalone nodes, harvest their style+content into a `_node_pseudo` sidecar keyed to the originating node id (direct `parentIndex` lookup, drop on miss), and redact the `content` vector at packaging. Mirrors the landed `_node_colors`/`_node_style` (cut-1/cut-2) pipeline.

**Tech Stack:** Python 3, CDP `DOMSnapshot.captureSnapshot`, pytest. Files under `scripts/` + a host-gate fixture under `fixtures/css_style/`.

**Spec:** `docs/plans/regime2-pseudo-element-capture-design.md`.

**Standing constraints (every task):** Single-line commit messages, NO trailers / NO `Co-Authored-By` / NO body. Stage files EXPLICITLY by path — NEVER `git add -A`/`git add .`. ONE commit per task (a review-driven fix gets its own commit). Do NOT push — all work local on master. The host gate (Task 7) runs on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox).

---

### Task 1: `_style` — `content` redactor + per-node pseudo redaction (pure core)

**Files:**
- Modify: `scripts/_style.py`
- Test: `scripts/test_style.py`

`content` is the one new content vector. It is a TOKEN LIST (`"label" counter(x) url(...) open-quote / "alt"`), so it must be tokenized and classified per token — a naive regex sub corrupts state because `url("http://x")` contains a quoted string and the marker `url("<asset>")` does too.

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_style.py`:

```python
from _style import redact_content_value, redact_pseudo  # noqa: E402


def test_content_string_redacted_to_text_marker():
    assert redact_content_value('"Read more"') == '"<text>"'
    assert redact_content_value("'Menu'") == '"<text>"'


def test_content_glyph_and_attr_resolved_redacted():
    assert redact_content_value('"→"') == '"<text>"'      # decorative glyph
    assert redact_content_value('"LABEL"') == '"<text>"'        # attr() resolved to a literal


def test_content_counter_and_quote_keywords_kept():
    assert redact_content_value("counter(foo)") == "counter(foo)"
    assert redact_content_value("counters(item, '.')") == "counters(item, '.')"
    assert redact_content_value("open-quote") == "open-quote"


def test_content_external_url_redacted_internal_kept():
    assert redact_content_value('url("https://a/b.png")') == 'url("<asset>")'
    assert redact_content_value('url("#frag")') == 'url("#frag")'


def test_content_mixed_url_and_string():
    assert redact_content_value('url("http://a/x.png") " label"') == 'url("<asset>") "<text>"'


def test_content_alt_text_form():
    assert redact_content_value('"icon" / "alt label"') == '"<text>" / "<text>"'


def test_content_empty_string_kept():
    assert redact_content_value('""') == '""'        # no text to redact


def test_content_none_normal_passthrough():
    assert redact_content_value("none") == "none"
    assert redact_content_value("normal") == "normal"
    assert redact_content_value(None) is None


def test_content_idempotent():
    once = redact_content_value('"Read more"')
    assert redact_content_value(once) == once         # "<text>" stays "<text>"
    u = redact_content_value('url("http://a/x.png")')
    assert redact_content_value(u) == u               # url("<asset>") stays


def test_redact_pseudo_redacts_content_and_box_url():
    pseudos = {"::before": {"content": '"Buy now"', "color": "rgb(1, 2, 3)"},
               "::after": {"background-image": 'url("https://a/b.png")', "content": '""'}}
    out = redact_pseudo(pseudos)
    assert out["::before"]["content"] == '"<text>"'
    assert out["::before"]["color"] == "rgb(1, 2, 3)"          # box value untouched
    assert out["::after"]["background-image"] == 'url("<asset>")'
    assert out["::after"]["content"] == '""'


def test_redact_pseudo_none_safe():
    assert redact_pseudo(None) is None
    assert redact_pseudo({}) == {}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py -q`
Expected: FAIL — `ImportError: cannot import name 'redact_content_value'`.

- [ ] **Step 3: Implement** — append to `scripts/_style.py` (after `redact_node_styles`):

```python
# A `content` value is a TOKEN LIST: '"label" counter(x) url(...) open-quote / "alt"'.
# Tokenize and classify each token so a url()'s inner quoted string is never
# re-redacted, and the url("<asset>")/"<text>" markers are never re-hit (idempotence).
_CONTENT_TOKEN = re.compile(r"""
      url\(\s*(['"]?).*?\1\s*\)        # url(...) — quoted or bare
    | "(?:[^"\\]|\\.)*"                 # double-quoted string
    | '(?:[^'\\]|\\.)*'                 # single-quoted string
    | counters?\([^)]*\)               # counter()/counters()
    | /                                # alt-text separator
    | [^\s/]+                          # bareword keyword (open-quote, none, ...)
""", re.I | re.X | re.S)
_TEXT = '"<text>"'


def redact_content_value(content):
    """Redact a resolved pseudo-element `content` value (the one Regime-2 content
    vector). content is a token list; tokenize and classify each token:
    quoted strings (incl. attr-resolved literals) -> "<text>" (empty "" kept — no
    text to redact); external/data url() -> url("<asset>") via redact_style_value;
    same-doc url(#frag), counter()/counters(), the '/' alt separator, and quote
    keywords are kept (mechanism). none/normal/empty pass through unchanged."""
    if not content:
        return content
    if content.strip().lower() in ("none", "normal", ""):
        return content
    out = []
    for m in _CONTENT_TOKEN.finditer(content):
        tok = m.group(0)
        if tok[:4].lower() == "url(":
            out.append(redact_style_value(tok))
        elif tok[:1] in ("'", '"'):
            out.append(tok if len(tok) <= 2 else _TEXT)   # "" (empty) kept; text -> marker
        else:
            out.append(tok)                                # counter()/keyword/'/'
    return " ".join(out)


def redact_pseudo(pseudos):
    """Redact one node's pseudo map {selector: {prop: raw value}}: the `content`
    prop uses redact_content_value; every other prop reuses redact_style_value (the
    box url() vector — a pseudo background-image/filter). None/empty-safe."""
    if not pseudos:
        return pseudos
    return {sel: {p: (redact_content_value(v) if p == "content"
                      else redact_style_value(v))
                  for p, v in style.items()}
            for sel, style in pseudos.items()}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py -q`
Expected: PASS (all `test_style.py` tests green).

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add pseudo-element content redactor + per-node pseudo redaction to _style"
```

---

### Task 2: `web_skeleton` — capture the `content` column + read `pseudoType` per record

**Files:**
- Modify: `scripts/web_skeleton.py` (`WANT_STYLES` near line 49; `parse_snapshot` near lines 167 and 176)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_web_skeleton.py`:

```python
def test_want_styles_includes_content_not_in_style_props():
    assert "content" in ws.WANT_STYLES
    assert "content" not in ws.STYLE_PROPS   # real elements resolve content->normal


def test_parse_snapshot_reads_pseudo_type():
    # pseudoType is sparse RareStringData: node index 1 is a ::before; value strings
    # are CDP's bare kinds ("before"/"after"/"marker"), NOT the "::"-prefixed name.
    S = ["", "DIV", "before"]
    full = [-1] * len(WANT)
    snap = {"strings": S, "documents": [{
        "nodes": {"nodeName": [1, 1], "parentIndex": [-1, 0],
                  "pseudoType": {"index": [1], "value": [_idx(S, "before")]}},
        "layout": {"nodeIndex": [0, 1], "bounds": [[0, 0, 10, 10], [0, 0, 5, 5]],
                   "paintOrders": [0, 1], "text": [-1, -1],
                   "styles": [full, full]}}]}
    recs = ws.parse_snapshot(snap, WANT)
    assert recs[0].get("pseudo") is None        # real DIV
    assert recs[1].get("pseudo") == "before"    # the ::before node


def test_parse_snapshot_no_pseudo_type_is_none():
    # legacy/synthetic snapshots without pseudoType -> every record pseudo=None.
    recs = ws.parse_snapshot(_snap(), WANT)
    assert all(r.get("pseudo") is None for r in recs)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q -k "content_not_in_style_props or pseudo_type"`
Expected: FAIL — `test_want_styles_includes_content_not_in_style_props` fails (`content` not yet in `WANT_STYLES`) and the `pseudo` tests fail (`recs[1].get("pseudo")` is `None`, not `"before"`).

- [ ] **Step 3a: Append `content` to `WANT_STYLES`** — in `scripts/web_skeleton.py`, after the cut-2 block ending `"perspective", "transform-style", "rotate", "scale", "translate",` (line 49), insert before the closing `]`:

```python
    # Regime-2: pseudo-element generated content. APPENDED (parallel-index contract —
    # keeps every existing index stable). Resolved RAW (literal text / counter() /
    # url()); redacted at packaging (_style.redact_content_value). NOT added to
    # STYLE_PROPS — real elements resolve content->normal; only pseudo rows
    # (::before/::after/::marker) carry a meaningful value.
    "content",
```

- [ ] **Step 3b: Read `pseudoType` in `parse_snapshot`** — in `scripts/web_skeleton.py`, immediately after the `captured_frames = set(...)` line (line 167), insert:

```python
        # Regime-2: pseudoType is sparse RareStringData ({index:[node_idx],
        # value:[strIdx]}). Map node index -> pseudo kind ("before"/"after"/"marker")
        # so each record can carry r["pseudo"]; None for real elements.
        pt = nodes.get("pseudoType") or {}
        pseudo_by_node = {idx: s(val)
                          for idx, val in zip(pt.get("index", []), pt.get("value", []))}
```

- [ ] **Step 3c: Add `pseudo` to the record dict** — in the same `out.append({...})` call, add a line after `"substrate": classify_substrate(...)` (line 185):

```python
                "pseudo": pseudo_by_node.get(dom_i),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q`
Expected: PASS. The parallel-index pin (`test_want_styles_parallel_index_stable_after_extension`) and `STYLE_PROPS ⊆ WANT_STYLES` (`test_style_props_subset_of_want_styles`) stay green with `content` appended.

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: capture content column + read pseudoType per record in web_skeleton parse"
```

---

### Task 3: `web_skeleton` — `_collect_pseudo` sparse collector (pure)

**Files:**
- Modify: `scripts/web_skeleton.py` (add after `_collect_style`, near line 134)
- Test: `scripts/test_web_skeleton.py`

`_collect_style` excludes `color`/`background-color`/`border-top-color` (they live in the `_node_colors` model) and never reads `content`. A pseudo needs all of those — `color` is `::marker`'s entire signal. Because `color` INHERITS, it is emitted only when it differs from the originating element's resolved color, so a default `::marker` (which matches its list's text color) does not land on every `<li>`.

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_web_skeleton.py`:

```python
def test_collect_pseudo_box_props_via_collect_style():
    st = {"text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "filter": "blur(2px)",
          "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
          "content": "normal"}
    out = ws._collect_pseudo(st, parent_color="rgb(0, 0, 0)")
    assert out["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert out["filter"] == "blur(2px)"
    assert "color" not in out                   # equals parent -> dropped
    assert "background-color" not in out         # transparent -> dropped
    assert "content" not in out                  # normal -> dropped


def test_collect_pseudo_color_only_when_differs_from_parent():
    # a custom ::marker color on a black-text list -> captured
    assert ws._collect_pseudo({"color": "rgb(255, 0, 0)"}, parent_color="rgb(0, 0, 0)") \
        == {"color": "rgb(255, 0, 0)"}
    # a default marker inherits the parent's color -> dropped (stays sparse)
    assert ws._collect_pseudo({"color": "rgb(0, 0, 0)"}, parent_color="rgb(0, 0, 0)") == {}


def test_collect_pseudo_content_and_bg_kept():
    out = ws._collect_pseudo(
        {"content": '"Read more"', "background-color": "rgb(1, 2, 3)"},
        parent_color="rgb(0, 0, 0)")
    assert out["content"] == '"Read more"'       # RAW (redacted at packaging)
    assert out["background-color"] == "rgb(1, 2, 3)"


def test_collect_pseudo_border_top_color_gated_on_style():
    assert "border-top-color" not in ws._collect_pseudo(
        {"border-top-color": "rgb(9, 9, 9)"}, parent_color=None)
    out = ws._collect_pseudo(
        {"border-top-style": "solid", "border-top-color": "rgb(9, 9, 9)"}, parent_color=None)
    assert out["border-top-style"] == "solid"    # via _collect_style
    assert out["border-top-color"] == "rgb(9, 9, 9)"


def test_collect_pseudo_empty_when_nothing_set():
    assert ws._collect_pseudo({"color": "rgb(0, 0, 0)", "content": "none"},
                              parent_color="rgb(0, 0, 0)") == {}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q -k collect_pseudo`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute '_collect_pseudo'`.

- [ ] **Step 3: Implement** — in `scripts/web_skeleton.py`, after `_collect_style` (line 134) and before `parse_snapshot`, add:

```python
_PSEUDO_SELECTORS = {"before", "after", "marker"}


def _collect_pseudo(st, parent_color):
    """Sparse style for a pseudo-element (::before/::after/::marker) from its
    resolved style row. Reuses _collect_style for the cut-1/cut-2 box props, then
    adds the fg/bg/border-top-color the _node_colors model excludes (here inline as
    resolved rgb(), content-free) and the redaction-deferred `content`:
      - color (fg) ONLY when it differs from the originating element's resolved color
        (parent_color) — color inherits, so a default ::marker matches its list's text
        color and must NOT land on every <li>;
      - background-color when not transparent; border-top-color gated on border-top-style;
      - content (RAW; redacted at packaging) when not none/normal/empty.
    Geometry (the pseudo's bbox/size) is NOT captured (deferred). {} when nothing set."""
    out = _collect_style(st)
    bg = st.get("background-color")
    if bg is not None and bg.strip().lower() not in _TRANSPARENT:
        out["background-color"] = bg
    bts = st.get("border-top-style")
    if bts and bts.strip().lower() not in _STYLE_NOOP:
        btc = st.get("border-top-color")
        if btc and btc.strip():
            out["border-top-color"] = btc
    color = st.get("color")
    if color and color.strip() and color != parent_color:
        out["color"] = color
    content = st.get("content")
    if content is not None and content.strip().lower() not in ("none", "normal", ""):
        out["content"] = content
    return out
```

(`_TRANSPARENT` and `_STYLE_NOOP` are existing module globals; `_TRANSPARENT` is defined at line 191, AFTER `_collect_style` — that is fine because `_collect_pseudo` only references it at call time, not at definition.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q -k collect_pseudo`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add _collect_pseudo sparse style+content collector to web_skeleton"
```

---

### Task 4: `web_skeleton` — route pseudo records into a `_node_pseudo` sidecar

**Files:**
- Modify: `scripts/web_skeleton.py` (`to_skeleton` lines 339-409; `_snapshot_skeleton` lines 498-504)
- Test: `scripts/test_web_skeleton.py` (new tests + update 4 existing `to_skeleton` unpack sites)

`to_skeleton` gains a 4th return value `node_pseudo`. Pseudo records are skipped from standalone emission (this also FIXES a latent bug — today a `::before` record reaches `classify` and is emitted as a junk `text`/`unknown_box` node) and harvested into the sidecar via a DIRECT parent lookup (drop on miss — never reattach to a grandparent).

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_web_skeleton.py`:

```python
def test_to_skeleton_attaches_pseudo_to_origin_not_standalone():
    # a DIV (emitted) with a ::before record -> the ::before does NOT become its own
    # node; it attaches to the DIV's node id. Color differs from parent -> captured.
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
         "z": 0, "text": None, "substrate": None, "pseudo": None,
         "style": {"display": "block", "color": "rgb(0, 0, 0)", "border-top-width": "2px"}},
        {"dom_index": 1, "tag": "::BEFORE", "bbox": {"x": 0, "y": 0, "w": 12, "h": 12},
         "z": 0, "text": None, "substrate": None, "pseudo": "before",
         "style": {"color": "rgb(255, 0, 0)", "content": '"Read more"'}},
    ]
    sk, node_colors, node_style, node_pseudo = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    assert len(sk["nodes"]) == 1                    # the ::before is NOT a node
    nid = sk["nodes"][0]["id"]
    assert node_pseudo[nid]["::before"]["color"] == "rgb(255, 0, 0)"
    assert node_pseudo[nid]["::before"]["content"] == '"Read more"'   # RAW


def test_to_skeleton_drops_orphan_pseudo_with_unemitted_parent():
    # a ::before whose parent (dom 0) is zero-area (classify -> None, not emitted)
    # must be DROPPED, never reattached to an ancestor.
    recs = [
        {"dom_index": 0, "tag": "DIV", "bbox": {"x": 0, "y": 0, "w": 0, "h": 0},
         "z": 0, "text": None, "substrate": None, "pseudo": None, "style": {}},
        {"dom_index": 1, "tag": "::BEFORE", "bbox": {"x": 0, "y": 0, "w": 5, "h": 5},
         "z": 0, "text": None, "substrate": None, "pseudo": "before",
         "style": {"content": '"x"'}},
    ]
    sk, _, _, node_pseudo = ws.to_skeleton(
        recs, svg_set=set(), parent_index=[-1, 0], url="u",
        viewport={"w": 100, "h": 100, "dpr": 1}, page={"w": 100, "h": 100})
    assert sk["nodes"] == []          # parent not emitted
    assert node_pseudo == {}          # orphan pseudo dropped, NOT reattached
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q -k "attaches_pseudo_to_origin or orphan_pseudo"`
Expected: FAIL — `ValueError: not enough values to unpack (expected 4, got 3)` (`to_skeleton` still returns a 3-tuple).

- [ ] **Step 3a: Skip pseudo records from emission** — in `scripts/web_skeleton.py`, in `to_skeleton`'s `for r in recs:` loop (line 350), make the first line of the loop body:

```python
    for r in recs:
        if r.get("pseudo"):
            continue   # pseudo-elements are not standalone nodes — harvested below
        role = classify(r, in_svg=(r["dom_index"] in svg_set))
        if role is None:
            continue
```

- [ ] **Step 3b: Harvest the `_node_pseudo` sidecar** — in `to_skeleton`, replace the block from `pm = build_parent_map(` (line 394) through the `return` (line 409) with:

```python
    # Regime-2: attach each ::before/::after/::marker to its ORIGINATING element's
    # node id via a DIRECT parent lookup (drop on miss — never reattach to an
    # ancestor). parent_color (for _collect_pseudo's color parent-diff) is the
    # originating node's captured fg. Mirrors the _node_colors/_node_style sidecars.
    dom_to_id = {n["_dom_index"]: n["id"] for n in emitted}
    node_pseudo = {}
    for r in recs:
        ps = r.get("pseudo")
        if ps not in _PSEUDO_SELECTORS:
            continue
        nid = dom_to_id.get(parent_index[r["dom_index"]])
        if nid is None:
            continue
        sv = _collect_pseudo(r["style"], (node_colors.get(nid) or {}).get("fg"))
        if sv:
            node_pseudo.setdefault(nid, {})["::" + ps] = sv

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
    return skeleton, node_colors, node_style, node_pseudo
```

- [ ] **Step 3c: Update the `to_skeleton` docstring return line** — change the `Returns (skeleton, node_colors, node_style) where ...` sentence (lines 343-346) to read `Returns (skeleton, node_colors, node_style, node_pseudo)`; append: `node_pseudo is {node_id: {"::before"|"::after"|"::marker": sparse-style}} (Regime-2), keyed to the ORIGINATING element via a direct parentIndex lookup.`

- [ ] **Step 3d: Thread the sidecar through `_snapshot_skeleton`** — in `scripts/web_skeleton.py`, change the `to_skeleton(...)` unpack (line 498) and add the str-keyed assignment after line 504:

```python
    sk, node_colors, node_style, node_pseudo = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads these; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    sk["_node_style"] = {str(k): v for k, v in node_style.items()}
    sk["_node_pseudo"] = {str(k): v for k, v in node_pseudo.items()}
    return sk, layout, page
```

- [ ] **Step 3e: Update the 4 existing `to_skeleton` unpack sites in the test file** — in `scripts/test_web_skeleton.py`:
  - line 228: `sk, node_colors, _ = ws.to_skeleton(` → `sk, node_colors, _, _ = ws.to_skeleton(`
  - line 263: `sk, _, _ = ws.to_skeleton(` → `sk, _, _, _ = ws.to_skeleton(`
  - line 373: `sk, _, _ = ws.to_skeleton(` → `sk, _, _, _ = ws.to_skeleton(`
  - line 617: `sk, node_colors, node_style = ws.to_skeleton(` → `sk, node_colors, node_style, _ = ws.to_skeleton(`

  (Leave `_capture_one` unpack sites at lines 537/550 alone — they unpack `_capture_one`, which still returns a 3-tuple, and the monkeypatched `_snapshot_skeleton` fakes at lines 533/548 also still return their own 3-tuple `(sk, layout, page)` — unchanged.)

- [ ] **Step 4: Run the full web_skeleton suite to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py -q`
Expected: PASS (all tests, including the 4 updated unpack sites and the 2 new pseudo tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: route pseudo-element records into a _node_pseudo sidecar in to_skeleton"
```

---

### Task 5: `bundle_writer` — attach the redacted per-node `pseudo` field

**Files:**
- Modify: `scripts/bundle_writer.py` (`apply_node_style` region near line 147; `assemble` line 149; `main` near line 221)
- Test: `scripts/test_bundle_writer.py`

`apply_node_pseudo` mirrors `apply_node_style`: it runs BEFORE `cf.redact_node`, which preserves the `pseudo` key (it is not a `CONTENT_KEYS` entry, and `redact_node` filters only top-level keys, so the nested redacted `content` survives).

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_bundle_writer.py`:

```python
def test_apply_node_pseudo_redacts_and_attaches():
    nodes = [{"id": 0, "role": "box"}, {"id": 1, "role": "box"}]
    node_pseudo = {0: {"::before": {"content": '"Buy now"', "color": "rgb(1, 2, 3)"},
                       "::after": {"background-image": 'url("https://cdn/x.png")'}}}
    bw.apply_node_pseudo(nodes, node_pseudo)
    assert nodes[0]["pseudo"]["::before"]["content"] == '"<text>"'
    assert nodes[0]["pseudo"]["::before"]["color"] == "rgb(1, 2, 3)"
    assert nodes[0]["pseudo"]["::after"]["background-image"] == 'url("<asset>")'
    assert "pseudo" not in nodes[1]              # no entry -> no field


def test_apply_node_pseudo_none_is_noop():
    nodes = [{"id": 0, "role": "box"}]
    bw.apply_node_pseudo(nodes, None)
    assert "pseudo" not in nodes[0]


def test_assemble_attaches_pseudo_surviving_redact_node():
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_pseudo = {0: {"::before": {"content": '"hi"', "color": "rgb(1, 2, 3)"}}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={},
                         node_pseudo=node_pseudo)
    ps = bundle["skeleton"]["nodes"][0]["pseudo"]
    assert ps["::before"]["content"] == '"<text>"'    # survived redact_node
    assert ps["::before"]["color"] == "rgb(1, 2, 3)"


def test_write_bundle_with_external_url_pseudo_audits_clean(tmp_path):
    # round-trip: a _node_pseudo with an external url + a long authored string ->
    # redacted on disk -> audit passes; the raw prose is absent.
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None}],
                "_node_pseudo": {"0": {"::after": {
                    "background-image": 'url("https://cdn.example.com/x.png")',
                    "content": '"Handcrafted urushi lacquer keyboard by artisans"'}}}}
    raw = skeleton.pop("_node_pseudo")
    node_pseudo = {int(k): v for k, v in raw.items()}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={},
                         node_pseudo=node_pseudo)
    bw.write_bundle(bundle, tmp_path)   # raises ContentLeak if redaction failed
    import json as _json
    text = (tmp_path / "skeleton.json").read_text()
    ps = _json.loads(text)["nodes"][0]["pseudo"]["::after"]
    assert ps["background-image"] == 'url("<asset>")'
    assert ps["content"] == '"<text>"'
    assert "Handcrafted" not in text     # raw prose absent on disk
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py -q -k pseudo`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_pseudo'`.

- [ ] **Step 3a: Add `apply_node_pseudo`** — in `scripts/bundle_writer.py`, after `apply_node_style` (line 147), add:

```python
def apply_node_pseudo(nodes, node_pseudo):
    """Attach each node's captured pseudo-element map as node["pseudo"], redacted by
    _style (content -> "<text>"; external/data url() -> url("<asset>")). node_pseudo:
    {node_id: {selector: {prop: raw value}}}. Runs BEFORE cf.redact_node, which
    preserves the `pseudo` key (not a CONTENT_KEYS entry; redact_node filters only
    top-level keys, so the nested redacted content survives). No entry -> no field."""
    if not node_pseudo:
        return
    for n in nodes:
        pv = node_pseudo.get(n["id"])
        if pv:
            n["pseudo"] = _style.redact_pseudo(pv)
```

- [ ] **Step 3b: Thread `node_pseudo` through `assemble`** — change the `assemble` signature (line 149) and add the call after `apply_node_style(nodes, node_style)` (line 156):

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None):
    """Build the in-memory bundle: meta + skeleton (with anim_ref/token_ref
    filled) + tokens + motion + assets/manifest. Mutates skeleton nodes in place
    to set anim_ref and token_ref."""
    nodes = skeleton["nodes"]
    palette = tokens.get("palette", {})
    apply_token_refs(nodes, palette, node_colors)
    apply_node_style(nodes, node_style)
    apply_node_pseudo(nodes, node_pseudo)
```

(Leave the rest of `assemble` unchanged — `match_motion`, `build_slots`, `collect_substrate`, the `cf.redact_node` emit pass, and the `bundle` dict.)

- [ ] **Step 3c: Pop `_node_pseudo` in `main`** — in `scripts/bundle_writer.py`, after the `_node_style` pop (lines 221-222), add:

```python
    raw_pseudo = skeleton.pop("_node_pseudo", {})
    node_pseudo = {int(k): v for k, v in raw_pseudo.items()}
```

  and pass it to `assemble` (the existing call at line 229) by adding the kwarg:

```python
    bundle = assemble(skeleton, tokens, node_colors, motion_rows,
                      meta_extra={"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                             time.gmtime())},
                      node_style=node_style, node_pseudo=node_pseudo)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: PASS (all bundle_writer tests, incl. the 4 new pseudo tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: attach redacted per-node pseudo field in bundle_writer"
```

---

### Task 6: `content_firewall` — pseudo bundle audits clean + canary (tests only)

**Files:**
- Test: `scripts/test_content_firewall.py`

No `content_firewall.py` change is needed: `pseudo` is not in `CONTENT_KEYS` (so `redact_node` keeps it — verified by Task 5), and `audit_bundle` already scans every nested string. These tests PIN that the invariant holds for the new field: a redacted pseudo audits clean, and an un-redacted external url inside a pseudo trips. (`audit_bundle` also catches authored prose ≥25 ASCII chars / ≥4 non-ASCII via `_PROSE`/`_NONASCII_PROSE`; only short ASCII strings rely solely on the Task-1 redactor.)

- [ ] **Step 1: Write the tests** — append to `scripts/test_content_firewall.py`:

```python
def test_audit_passes_skeleton_with_pseudo(tmp_path):
    # A node["pseudo"] carrying redacted content ("<text>"), inline rgb() colors, an
    # internal #ref clip-path and a redacted external bg audits clean — same
    # structured-token class as node["style"]; the content vector is already redacted.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {
                         "::before": {"content": '"<text>"', "color": "rgb(255, 0, 0)",
                                      "text-shadow": "rgb(0, 0, 0) 1px 1px 2px"},
                         "::after": {"background-image": 'url("<asset>")',
                                     "clip-path": 'url("#c")', "content": '""'},
                         "::marker": {"color": "rgb(0, 128, 0)"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []


def test_audit_canary_unredacted_url_in_pseudo_trips(tmp_path):
    # Proves the pseudo redaction is load-bearing: an UN-redacted external url in a
    # pseudo (here background-image) MUST trip the firewall.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo": {"::after": {
                         "background-image": 'url("https://cdn.example.com/x.png")'}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) != []
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_content_firewall.py -q -k pseudo`
Expected: PASS (the clean bundle returns `[]`; the un-redacted-url bundle returns a non-empty violation list). If `test_audit_passes_skeleton_with_pseudo` FAILS, an unexpected string in the fixture tripped a detector — fix the FIXTURE values (not `content_firewall.py`).

- [ ] **Step 3: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: pseudo-element bundle audits clean; un-redacted url in pseudo trips firewall"
```

---

### Task 7: Host gate — extend the offline css-style fixture with pseudo-elements

**Files:**
- Modify: `fixtures/css_style/run_css_style.py`

This is the deterministic, offline, **local-server** end-to-end gate (NOT a `data:` URL / `navigate` — the orientation probe proved `navigate` can silently capture a live tab). It serves a page with a `::before` (string content), an `::after` (a `url(/ext.png)` content — the url-in-content redaction exerciser, served by the same local server), and a custom `li::marker { color }`, then drives `web_skeleton → bundle_writer` and asserts the on-disk `node["pseudo"]`.

- [ ] **Step 1: Extend the page CSS + markup** — in `fixtures/css_style/run_css_style.py`, inside the `_PAGE` `<style>` block (after the `#plain` rule, line 56), add:

```css
  #pb { width: 60px; height: 20px; }
  #pb::before { content: "Handcrafted urushi lacquer keyboard"; color: rgb(200,10,10);
                display: block; width: 12px; height: 12px; }
  #pa { width: 60px; height: 20px; }
  #pa::after { content: url(/ext.png); display: inline-block; width: 10px; height: 10px; }
  ol li::marker { color: rgb(0,128,0); }
```

  and after the `<div id=plain></div>` markup line (line 63), add:

```html
<div id=pb></div>
<div id=pa></div>
<ol><li>item</li></ol>
```

- [ ] **Step 2: Extend `_check` with the pseudo assertions** — in `fixtures/css_style/run_css_style.py`, immediately before `return True` (line 179), insert:

```python
    # Regime-2: pseudo-elements attach to their originating node.
    pnodes = [n for n in nodes if n.get("pseudo")]
    print("pseudo nodes:", len(pnodes))
    # ::before string content -> redacted to "<text>"; custom color captured.
    pb = next((n for n in pnodes if (n["pseudo"].get("::before") or {}).get("content") == '"<text>"'), None)
    if pb is None:
        print("GATE FAIL: no ::before with redacted content '\"<text>\"';",
              json.dumps([n.get("pseudo") for n in pnodes]))
        return False
    if "rgb" not in (pb["pseudo"]["::before"].get("color") or ""):
        print("GATE FAIL: ::before color not captured:", json.dumps(pb["pseudo"]["::before"]))
        return False
    # ::after url() content -> redacted to url("<asset>") (url-in-content vector).
    pa = next((n for n in pnodes if (n["pseudo"].get("::after") or {}).get("content") == 'url("<asset>")'), None)
    if pa is None:
        print("GATE FAIL: ::after url() content not redacted to url(\"<asset>\");",
              json.dumps([n["pseudo"].get("::after") for n in pnodes if "::after" in n["pseudo"]]))
        return False
    # custom ::marker color captured (default markers, equal to parent text color, are absent).
    mk = next((n for n in pnodes if "rgb" in ((n["pseudo"].get("::marker") or {}).get("color") or "")), None)
    if mk is None:
        print("GATE FAIL: custom ::marker color not captured")
        return False
    # the raw authored ::before string must NOT appear anywhere on disk.
    if "Handcrafted" in json.dumps(disk):
        print("GATE FAIL: raw pseudo content leaked to disk")
        return False
    print("pseudo ok: ::before content redacted to <text> + color; ::after url() content redacted; custom ::marker color kept")
```

- [ ] **Step 3: Update the GATE PASS line + module docstring** — change the final pass message (line 193) to:

```python
        print("GATE PASS: Regime-1 + Regime-2 visual CSS captured + redacted; bundle audits clean.")
```

  and append one sentence to the module docstring (after line 14): `Also exercises Regime-2 pseudo-elements: a ::before (string content -> "<text>"), an ::after (url() content -> url("<asset>")), and a custom li::marker color, attached to their originating nodes.`

- [ ] **Step 4: Run the host gate**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/css_style/run_css_style.py`
(host Bash, `dangerouslyDisableSandbox=true` — CDP unreachable from the ctx sandbox)
Expected: stdout ends `GATE PASS: Regime-1 + Regime-2 ...`; exit code 0. If FAIL, fix the implementation (not the assertion) and re-run.

- [ ] **Step 5: Commit**

```bash
git add fixtures/css_style/run_css_style.py
git commit -m "test: extend css-style host gate with pseudo-element capture + redaction checks"
```

---

## After all tasks (controller, not a subagent)

1. **Full suite green:** `cd .../scripts && python3 -m pytest -q` — expected all pass.
2. **Real-site validation (one-off, content-free, NOT committed):** extend/clone `fixtures/css_style/validate_realsite.py` to also print `{pseudo-selector: occurrence-count}` (NEVER a `content` value, resolved string, or URL); run once against a chosen public page on host CDP; record the content-free summary in `docs/plans/probe-runner-engine-capture-gaps.md` §C9-R-P8 and add a "Regime-2 LANDED" note to `docs/research/css-capture-completeness.md`. (Doc-recording commit is separate, single-line.)
3. **Final review:** dispatch the whole-implementation reviewer per subagent-driven-development.

## Self-Review

**Spec coverage:** scope before/after/marker → `_PSEUDO_SELECTORS` (T3) + harvest filter (T4); `content` redact (string→`<text>`, counter/keyword kept, url→`<asset>`) → T1; direct join + drop-on-miss → T4; color parent-diff sparseness → T3; sidecar + leak-fix (pseudo not emitted as standalone) → T4; bundle attach surviving redact_node → T5; firewall clean + canary → T6; synthetic gate → T7; real-site run → After-all step 2. Honest ceilings (placeholder/selection/first-line not enumerated; geometry deferred; counter names kept) are documented in the spec, no task needed.

**Placeholder scan:** none — every code/test step carries full verbatim content and an exact run command.

**Type consistency:** `redact_content_value`/`redact_pseudo` (T1) ↔ `_style.redact_pseudo` in `apply_node_pseudo` (T5) ✓; `_collect_pseudo`/`_PSEUDO_SELECTORS` (T3) ↔ `to_skeleton` (T4) ✓; `to_skeleton` 4-tuple (T4) ↔ `_snapshot_skeleton` + 4 updated test unpack sites ✓; `assemble(..., node_pseudo=None)` + `node["pseudo"]` key consistent across T5/T6/T7 ✓.
