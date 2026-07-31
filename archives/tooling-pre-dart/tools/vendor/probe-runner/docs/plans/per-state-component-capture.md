# Per-state Component Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `web_states` records each driven G4 interaction state as a reproducible content-free *component* (revealed subtree re-rooted with structure + sizing + layout + font + colors + mount), not just appeared-node counts.

**Architecture:** A new pure core `build_component(rest, after)` in `scripts/_states.py` reuses the post-trigger `after` skeleton already captured in the per-trigger loop (no extra CDP trip). It selects revealed nodes with the SAME predicate as `diff_skeletons` (extracted to a shared `_matches_rest`), re-roots them with component-local parent ids, carries colors from the after-skeleton's `_node_colors` sidecar, and records each root's mount point. `web_states` adds an additive `component` key per state; schema stays `probe-states/1`.

**Tech Stack:** Python 3 (stdlib only), pytest. CDP host gate for the live path. Content-free invariant enforced by `content_firewall.audit_bundle`.

**Spec:** `docs/plans/per-state-component-capture-design.md`.

---

## File Structure

- `scripts/_states.py` (MODIFY) — pure core. Extract `_matches_rest`; add `build_component`. Owns the REST-match predicate (one definition, two callers) and the component re-rooting.
- `scripts/web_states.py` (MODIFY) — wiring only. Import + call `build_component` in the existing per-trigger loop; add the `component` key + a `components_built` summary field.
- `scripts/test_states.py` (MODIFY) — add `build_component` + `_matches_rest` unit tests; the existing `diff_skeletons` tests must keep passing UNCHANGED (regression guard for the extraction).
- `scripts/test_content_firewall.py` (MODIFY) — add a unit test proving a `states.json` carrying a component (colors + font + mount) audits content-free via the REAL `cf.audit_bundle` on a temp bundle dir. This is the firewall guarantee (deterministic, no host Chrome), NOT the host gate.
- `fixtures/component/run_component.py` (CREATE) — deterministic offline CDP host gate: a click reveals a styled panel; assert the emitted `component` is structurally sound, carries the panel color (parsed, spacing/format-robust), resolves parents, and records a mount. Live structural proof only — the firewall is proven by the unit test above.
- `.gitignore` (MODIFY) — ignore `fixtures/component/_out.json`.
- `docs/plans/probe-runner-engine-capture-gaps.md` + `CONTEXT.md` (controller, post-gate) — append the `§C9-R-P4` results record and a CONTEXT.md State-glossary note. NOT a subagent task (the record describes host-gate outcomes only the controller observes — mirrors P3-G6).

---

### Task 1: Extract the REST-match predicate (`_matches_rest`)

Behavior-preserving refactor: pull the per-node match test out of `diff_skeletons` into a private `_matches_rest`, so `build_component` (Task 2) can share the EXACT same definition. `diff_skeletons`' output must not change.

**Files:**
- Modify: `scripts/_states.py` (the `diff_skeletons` function)
- Test: `scripts/test_states.py`

- [ ] **Step 1: Write the failing test**

In `scripts/test_states.py`, change the existing import line `from _states import classify_trigger` to:

```python
from _states import classify_trigger, diff_skeletons, _matches_rest
```

(NOTE: `diff_skeletons` is already used by existing tests — it is currently imported; confirm the line ends up with all three names. `build_component` is added to this import in Task 2, not here, so Task 1 runs in isolation.)

Add this test (the `_node` helper already exists at the top of the diff tests — reuse it):

```python
def test_matches_rest_predicate():
    rest = [_node(0, "box", 0, 0, 1000, 50)]
    # same element, tiny shift -> matches (not revealed)
    assert _matches_rest(_node(9, "box", 2, 2, 1000, 50), rest, 24.0) is True
    # same role, same top-left corner, grown -> reflow match (not revealed)
    assert _matches_rest(_node(9, "box", 0, 0, 1000, 300), rest, 24.0) is True
    # fresh corner, different size -> NOT a match (revealed)
    assert _matches_rest(_node(9, "box", 400, 380, 200, 60), rest, 24.0) is False
    # role mismatch at the same spot -> NOT a match (revealed)
    assert _matches_rest(_node(9, "menuitem", 0, 0, 1000, 50), rest, 24.0) is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_states.py::test_matches_rest_predicate -q`
Expected: FAIL — `ImportError: cannot import name '_matches_rest'`.

- [ ] **Step 3: Extract the predicate**

In `scripts/_states.py`, add this function ABOVE `diff_skeletons` (after `_center`):

```python
def _matches_rest(a, rest_nodes, radius):
    """True if after-node `a` corresponds to a REST node (same element, possibly
    reflowed) — i.e. it is NOT revealed content. A match is same-role AND EITHER
    (a) center within `radius` px on both axes AND size within `radius` px on both
    dims (a small reflow shift = the SAME node), OR (b) top-left corners coincide
    within `radius` (the SAME element grew/reflowed in place — a page-root container
    like <body>/<html> growing taller is reflow, not revealed content).

    Extracted from diff_skeletons so diff_skeletons and build_component share ONE
    definition. See diff_skeletons' docstring for the documented under-count limit."""
    ab = a["bbox"]
    ac = _center(ab)
    for r in rest_nodes:
        if a.get("role") != r.get("role"):
            continue
        rb = r["bbox"]
        rc = _center(rb)
        same_box = (abs(ac[0] - rc[0]) <= radius and abs(ac[1] - rc[1]) <= radius
                    and abs(ab["w"] - rb["w"]) <= radius
                    and abs(ab["h"] - rb["h"]) <= radius)
        reflowed = (abs(ab["x"] - rb["x"]) <= radius and abs(ab["y"] - rb["y"]) <= radius)
        if same_box or reflowed:
            return True
    return False
```

Then rewrite the body of `diff_skeletons` to call it (KEEP the existing docstring verbatim — it documents the under-count limit that `_matches_rest` inherits):

```python
def diff_skeletons(rest, after, radius=24.0):
    """<<KEEP THE EXISTING DOCSTRING UNCHANGED>>"""
    rest_nodes = _nodes(rest)
    appeared = []
    for a in _nodes(after):
        if not _matches_rest(a, rest_nodes, radius):
            appeared.append({"role": a.get("role"), "bbox": a["bbox"], "z": a.get("z", 0)})
    return {"appeared": appeared, "n_appeared": len(appeared)}
```

- [ ] **Step 4: Run the WHOLE state suite (extraction must not change diff behavior)**

Run: `cd scripts && python3 -m pytest test_states.py -q`
Expected: PASS — all pre-existing tests (14) + `test_matches_rest_predicate` (15 total). The diff tests are the regression guard: if any diff test now fails, the extraction changed behavior — fix the predicate, do NOT edit the diff tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/_states.py scripts/test_states.py
git commit -m "refactor: extract _matches_rest predicate shared by diff_skeletons"
```

---

### Task 2: `build_component` — empty→None + subtree re-rooting + root mount

**Files:**
- Modify: `scripts/_states.py` (add `build_component`)
- Test: `scripts/test_states.py`

- [ ] **Step 1: Update the import + add the richer test-node helper + tests**

In `scripts/test_states.py`, extend the import to include `build_component`:

```python
from _states import classify_trigger, diff_skeletons, _matches_rest, build_component
```

Add this helper near `_node` (it adds `parent`/`sizing`/`layout`, which `build_component` carries through; `_node` lacks them):

```python
def _cn(nid, role, x, y, w, h, parent=None, z=0, sizing=None, layout=None, font=None):
    n = {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z,
         "parent": parent, "sizing": sizing, "layout": layout}
    if font is not None:
        n["font"] = font
    return n
```

Add the tests:

```python
def test_build_component_returns_none_when_nothing_revealed():
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)], "_node_colors": {}}
    assert build_component(rest, after) is None


def test_build_component_reroots_subtree_with_local_ids_and_mount():
    # REST: body + header. AFTER: body, header unchanged; a panel (child of body)
    # with two children appears. The panel mounts on body (a REST node).
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400), _cn(1, "box", 0, 0, 1000, 40)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                  # body (matches REST)
        _cn(1, "box", 0, 0, 1000, 40),                   # header (matches REST)
        _cn(2, "box", 100, 200, 300, 180, parent=0),     # NEW panel, mounts on body(0)
        _cn(3, "text", 110, 210, 280, 24, parent=2),     # NEW label, child of panel
        _cn(4, "box", 110, 240, 280, 120, parent=2),     # NEW item, child of panel
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    assert comp is not None
    assert comp["n_nodes"] == 3
    by_y = {n["bbox"]["y"]: n for n in comp["nodes"]}
    panel, label, item = by_y[200], by_y[210], by_y[240]
    # panel is a root: its after-parent (body) is a REST node, not revealed
    assert panel["parent"] is None
    assert panel["mount"] is not None
    assert panel["mount"]["role"] == "box"
    assert panel["mount"]["bbox"]["h"] == 400          # the body it mounts on
    # children re-rooted to the panel's component-local id
    assert label["parent"] == panel["id"]
    assert item["parent"] == panel["id"]
    assert label["mount"] is None and item["mount"] is None
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_states.py -k build_component -q`
Expected: FAIL — `ImportError: cannot import name 'build_component'`.

- [ ] **Step 3: Implement `build_component`**

In `scripts/_states.py`, add AFTER `diff_skeletons`:

```python
def build_component(rest, after, radius=24.0):
    """Build a reproducible, content-free mini-skeleton of the nodes revealed in
    `after` vs `rest` (post-trigger vs REST skeletons). Returns
    {"n_nodes": N, "nodes": [...]} or None when nothing was revealed.

    Each component node carries the content-free skeleton fields (role, bbox, z,
    sizing, layout, and `font` for text nodes) plus `colors` {bg, fg, border} from
    the after-skeleton's `_node_colors` sidecar, re-rooted with component-local
    parent ids (0..N-1 in revealed order). A component ROOT (its after-parent is a
    REST node, not itself revealed) records that parent as `mount` {role, bbox,
    colors}; non-roots have mount=None. The mount preserves the attach point AND a
    collapsed origin-anchored full-bleed modal container's backdrop colors (that
    container corner-matches <body>, so _matches_rest treats it as the mount, not a
    revealed node).

    Pure: `after` carries its own `_node_colors`; no browser. `new` uses the SAME
    predicate as diff_skeletons (`not _matches_rest`) over the same after-nodes, so
    n_nodes == that diff's n_appeared — a free cross-check."""
    rest_nodes = _nodes(rest)
    after_nodes = _nodes(after)
    colors = (after.get("_node_colors") if isinstance(after, dict) else None) or {}
    by_id = {n["id"]: n for n in after_nodes}

    new = [n for n in after_nodes if not _matches_rest(n, rest_nodes, radius)]
    if not new:
        return None
    new_ids = {n["id"] for n in new}
    local = {n["id"]: i for i, n in enumerate(new)}

    def _colors(node_id):
        c = colors.get(str(node_id)) or {}
        return {"bg": c.get("bg"), "fg": c.get("fg"), "border": c.get("border")}

    nodes = []
    for n in new:
        cn = {"id": local[n["id"]], "role": n.get("role"), "bbox": n["bbox"],
              "z": n.get("z", 0), "sizing": n.get("sizing"), "layout": n.get("layout"),
              "colors": _colors(n["id"])}
        if "font" in n:
            cn["font"] = n["font"]
        pid = n.get("parent")
        if pid in new_ids:
            cn["parent"] = local[pid]
            cn["mount"] = None
        else:
            cn["parent"] = None
            mp = by_id.get(pid) if pid is not None else None
            cn["mount"] = ({"role": mp.get("role"), "bbox": mp["bbox"],
                            "colors": _colors(pid)} if mp is not None else None)
        nodes.append(cn)
    return {"n_nodes": len(new), "nodes": nodes}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_states.py -k build_component -q`
Expected: PASS (2 build_component tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_states.py scripts/test_states.py
git commit -m "feat: add build_component pure core for per-state component capture"
```

---

### Task 3: colors + font carry-through (None-safe sidecar)

**Files:**
- Test: `scripts/test_states.py`
- (No `_states.py` change expected — `build_component` already reads `_node_colors` and copies `font`. This task PROVES it and pins None-safety.)

- [ ] **Step 1: Write the test**

Add to `scripts/test_states.py`:

```python
def test_build_component_carries_colors_and_font_none_safe():
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                                  # body (matches)
        _cn(1, "box", 100, 200, 300, 180, parent=0,                      # NEW panel, HAS colors
            sizing={"w": "fixed", "h": "hug", "confidence": "high"},
            layout={"mode": "flex", "direction": "column"}),
        _cn(2, "text", 110, 210, 280, 24, parent=1,                      # NEW label, HAS font + colors
            font={"size": 16.0, "weight": 700, "family": "sans"}),
        _cn(3, "box", 110, 240, 280, 60, parent=1),                      # NEW item, NO color entry
    ], "_node_colors": {
        "1": {"bg": "rgb(20,20,28)", "fg": "rgb(240,240,240)", "border": None},
        "2": {"bg": None, "fg": "rgb(200,200,200)", "border": None},
        # id 3 deliberately absent -> None-safe
    }}
    comp = build_component(rest, after)
    by_y = {n["bbox"]["y"]: n for n in comp["nodes"]}
    panel, label, item = by_y[200], by_y[210], by_y[240]
    # colors carried from the sidecar
    assert panel["colors"]["bg"] == "rgb(20,20,28)"
    assert label["colors"]["fg"] == "rgb(200,200,200)"
    # missing sidecar entry -> all-None colors, no KeyError
    assert item["colors"] == {"bg": None, "fg": None, "border": None}
    # sizing / layout carried verbatim
    assert panel["sizing"]["w"] == "fixed"
    assert panel["layout"]["mode"] == "flex"
    # font carried on the text node; absent on non-text nodes
    assert label["font"]["weight"] == 700
    assert "font" not in panel
```

- [ ] **Step 2: Run to verify behavior**

Run: `cd scripts && python3 -m pytest test_states.py::test_build_component_carries_colors_and_font_none_safe -q`
Expected: PASS (the Task-2 implementation already satisfies this). If it FAILS, the bug is in Task 2's `build_component` (the color/font copy) — fix `_states.py`, not the test.

NOTE: this is a deliberate characterization test confirming the spec's fork-B reuse. It is allowed to pass on first run; its value is locking the contract against regressions.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_states.py
git commit -m "test: pin build_component colors/font/sizing carry-through and None-safety"
```

---

### Task 4: multi-root, modal-collapse mitigation, and the n_nodes==n_appeared invariant

**Files:**
- Test: `scripts/test_states.py`
- (No `_states.py` change expected — these pin documented behaviors.)

- [ ] **Step 1: Write the tests**

Add to `scripts/test_states.py`:

```python
def test_build_component_multi_root():
    # One trigger reveals two DISJOINT subtrees (e.g. a menu + a tooltip), each
    # mounting on a different REST node -> two roots, each with its own mount.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400), _cn(1, "box", 800, 0, 200, 400)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                  # body (matches)
        _cn(1, "box", 800, 0, 200, 400),                 # sidebar (matches)
        _cn(2, "menu", 100, 200, 200, 150, parent=0),    # NEW menu, mounts on body(0)
        _cn(3, "tooltip", 820, 50, 160, 40, parent=1),   # NEW tooltip, mounts on sidebar(1)
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    assert comp["n_nodes"] == 2
    roots = [n for n in comp["nodes"] if n["parent"] is None]
    assert len(roots) == 2
    mounts = sorted(r["mount"]["bbox"]["x"] for r in roots)
    assert mounts == [0, 800]                             # body and sidebar


def test_build_component_modal_collapse_preserves_backdrop_via_mount():
    # The honest-ceiling case (mirrors test_diff_corner_rule_under_counts_...):
    # an origin-anchored full-bleed modal container corner-matches <body>, so
    # _matches_rest treats it as REST (the mount), NOT a revealed node. Its child
    # at a fresh corner IS revealed. The modal's own backdrop colors survive via
    # the child's mount.colors -> near-zero information loss.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 50),                   # body (unchanged)
        _cn(1, "box", 0, 0, 1000, 800, parent=0),        # NEW full-bleed modal at origin -> collapses to mount
        _cn(2, "box", 400, 380, 200, 60, parent=1),      # modal child at a fresh corner -> revealed
    ], "_node_colors": {
        "1": {"bg": "rgba(0,0,0,0.6)", "fg": None, "border": None},  # the modal backdrop
        "2": {"bg": "rgb(255,255,255)", "fg": None, "border": None},
    }}
    comp = build_component(rest, after)
    # only the modal child is a first-class component node (the modal box collapsed)
    assert comp["n_nodes"] == 1
    child = comp["nodes"][0]
    assert child["parent"] is None
    assert child["bbox"]["x"] == 400
    # the collapsed modal's geometry AND backdrop color survive as the mount
    assert child["mount"]["bbox"]["h"] == 800
    assert child["mount"]["colors"]["bg"] == "rgba(0,0,0,0.6)"


def test_n_nodes_equals_n_appeared_invariant():
    # build_component's `new` and diff_skeletons' `appeared` share the predicate
    # over the same after-nodes -> counts must agree for every input.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 50),
        _cn(1, "box", 0, 0, 1000, 800, parent=0),        # collapses (matches body corner)
        _cn(2, "box", 400, 380, 200, 60, parent=1),      # revealed
        _cn(3, "text", 410, 390, 180, 20, parent=2),     # revealed
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    d = diff_skeletons(rest, after)
    assert comp["n_nodes"] == d["n_appeared"] == 2
```

- [ ] **Step 2: Run to verify**

Run: `cd scripts && python3 -m pytest test_states.py -k "multi_root or modal_collapse or invariant" -q`
Expected: PASS (the Task-2 implementation already satisfies these — they pin the documented ceilings). If `modal_collapse` FAILS, the mount-colors path in `build_component` is wrong; fix `_states.py`.

- [ ] **Step 3: Run the full state suite**

Run: `cd scripts && python3 -m pytest test_states.py -q`
Expected: PASS — 14 pre-existing + `_matches_rest` + 2 (Task 2) + 1 (Task 3) + 3 (Task 4) = 21 tests.

- [ ] **Step 4: Commit**

```bash
git add scripts/test_states.py
git commit -m "test: pin build_component multi-root, modal-collapse, and count invariant"
```

---

### Task 5: Wire `build_component` into `web_states`

**Files:**
- Modify: `scripts/web_states.py` (import; the per-trigger loop; the `--out` summary)

- [ ] **Step 1: Update the import**

In `scripts/web_states.py`, change:

```python
from _states import classify_trigger, diff_skeletons
```

to:

```python
from _states import classify_trigger, diff_skeletons, build_component
```

- [ ] **Step 2: Build + attach the component in the per-trigger loop**

In the per-trigger `for tr in triggers[:args.max]:` loop, find:

```python
                d = diff_skeletons(pre, after)
                states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                               "appeared": d["appeared"]})
```

Replace with:

```python
                d = diff_skeletons(pre, after)
                comp = build_component(pre, after)
                states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                               "appeared": d["appeared"], "component": comp})
```

- [ ] **Step 3: Add the summary field**

In the `if args.out:` branch, find the summary `emit_json({...})` call and add a `components_built` key (count of states that produced a component — NOT a node total, which would duplicate `appeared_total` given the invariant):

```python
            emit_json({"ok": True, "out": args.out, "consent": consent,
                       "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                       "states": len(states),
                       "components_built": sum(1 for s in states if s["component"]),
                       "appeared_total": sum(s["n_appeared"] for s in states)})
```

(Leave `out_obj` as-is: each state dict already carries `component` from Step 2, so the written `states.json` includes it. Schema stays `probe-states/1`.)

- [ ] **Step 4: Verify the module imports and the full unit suite is green**

Run: `cd scripts && python3 -c "import web_states" && python3 -m pytest -q`
Expected: `import web_states` exits 0 (no syntax/import error); the FULL suite passes (prior baseline 240 + the new `test_states.py` cases → ~247). No web_states unit test exists (it is host-gated), so this step guards the import + the unchanged rest of the suite.

- [ ] **Step 5: Commit**

```bash
git add scripts/web_states.py
git commit -m "feat: emit per-state component on states.json from web_states"
```

---

### Task 6: Firewall unit test — a component on states.json is content-free

Proves the new `colors`/`font`/`mount` fields the component adds to `states.json` pass the REAL content firewall. Deterministic, no host Chrome — this is the content-free guarantee.

**Why this matters (load-bearing, verified 2026-05-31):** the component is the FIRST code path to write raw `rgb()`/`rgba()` color strings to an audited file. `tokens.json` ships HEX (`_hex`), and `_node_colors`' raw rgb is popped in `bundle_writer` (`skeleton.pop("_node_colors")`) and mapped to `token_ref` — it never reaches disk today. Empirically confirmed before planning: a `states.json` carrying a full component with `rgb(18, 52, 86)` + `rgba(0, 0, 0, 0.6)` audits clean (`cf.audit_bundle` → `[]`) — the firewall's text scan does NOT flag short structured CSS color tokens. This test pins that, so a future firewall tightening that would reject component colors is caught here.

**Files:**
- Test: `scripts/test_content_firewall.py`

- [ ] **Step 1: Write the test**

`scripts/test_content_firewall.py` already imports `content_firewall as cf` + `json` and defines `_clean_bundle(d)` (writes a minimal clean bundle dir). Append:

```python
def test_audit_passes_states_with_component(tmp_path):
    # A states.json carrying a per-state COMPONENT (re-rooted skeleton + colors +
    # font + mount) must audit content-free: raw rgb()/rgba() colors are short
    # structured CSS tokens the firewall's text scan does not flag (verified), font
    # family is exempt mechanism, role/bbox are geometry, selectors are structural.
    # No node text ever enters the component.
    d = _clean_bundle(tmp_path)
    states = {
        "schema": "probe-states/1", "url": "http://127.0.0.1/",
        "base_nodes": 10, "consent": None,
        "triggers_found": 1, "triggers_driven": 1,
        "states": [{
            "trigger": {"selector": "html > body > button:nth-of-type(1)",
                        "kind": "disclosure", "action": "click"},
            "n_appeared": 2,
            "appeared": [{"role": "region",
                          "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0}],
            "component": {"n_nodes": 2, "nodes": [
                {"id": 0, "role": "region",
                 "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0,
                 "sizing": {"w": "fixed", "h": "hug", "confidence": "high"},
                 "layout": {"mode": "block", "direction": "row"},
                 "colors": {"bg": "rgb(18, 52, 86)", "fg": "rgb(240, 240, 240)", "border": None},
                 "parent": None,
                 "mount": {"role": "box", "bbox": {"x": 0, "y": 0, "w": 1000, "h": 400},
                           "colors": {"bg": "rgba(0, 0, 0, 0)", "fg": None, "border": None}}},
                {"id": 1, "role": "text",
                 "bbox": {"x": 50, "y": 50, "w": 300, "h": 24}, "z": 0,
                 "sizing": {"w": "fill", "h": "hug", "confidence": "high"},
                 "layout": {"mode": "block", "direction": "row"},
                 "colors": {"bg": None, "fg": "rgb(200, 200, 200)", "border": None},
                 "font": {"size": 16.0, "weight": 700, "line_height": 24.0,
                          "letter_spacing": 0.0, "family": "sans-serif", "align": "left"},
                 "parent": 0, "mount": None}]}}]}
    (d / "states.json").write_text(json.dumps(states, indent=2))
    assert cf.audit_bundle(d) == []
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_content_firewall.py::test_audit_passes_states_with_component -q`
Expected: PASS — `cf.audit_bundle` returns `[]` (no violations). (Pre-verified in the sandbox 2026-05-31 with this exact payload shape.)
If it FAILS, the firewall flagged a component field. Read the violation: a raw rgb()/rgba() color string or a font stack should pass (the scan exempts short structured tokens + font mechanism). If a genuinely new content-bearing field slipped into the component, that is a DESIGN violation — stop and escalate, do NOT relax the firewall. Do NOT hex-normalize colors to dodge a failure: that would destroy modal-backdrop ALPHA, which `mount.colors` exists to preserve.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: pin states.json component payload is content-free"
```

---

### Task 7: Host gate — live component capture (CDP)

Deterministic, offline. Serves one page with a click affordance that reveals a STYLED panel (known bg + a text child). Runs `web_states` over CDP host Chrome, asserts the emitted `component` is structurally sound, carries the panel color (parsed → format-robust), resolves parents, and records a mount.

**Files:**
- Create: `fixtures/component/run_component.py`
- Modify: `.gitignore`

- [ ] **Step 1: Create the gate**

Create `fixtures/component/run_component.py` (mirrors `fixtures/consent/run_consent.py`'s server+subprocess shape):

```python
#!/usr/bin/env python3
"""Host gate: web_states captures a revealed panel as a reproducible component.

Deterministic, offline. Serves one page with a button (aria-expanded) whose
click reveals a hidden styled panel (known background color + a text child). Runs
web_states (CDP, host Chrome) and asserts states[*].component: the revealed
subtree is re-rooted (parent links resolve to valid component-local ids or null),
the panel's known bg color is carried (parsed -> spacing/format robust), n_nodes
matches len(nodes), and a root records a mount. The content-free guarantee is
proven separately by test_content_firewall.py (real cf.audit_bundle); this gate
proves the LIVE capture mechanism."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB_STATES = ROOT / "scripts" / "web_states.py"
sys.path.insert(0, str(ROOT / "scripts"))
from web_tokens import parse_color  # noqa: E402

PANEL_RGB = (18, 52, 86)  # #123456 — distinctive; matched via parse_color (format-robust)

# A button with aria-expanded=false (a drivable disclosure trigger) reveals a
# styled panel containing a label + an item. The panel is display:none at REST
# (genuinely revealed by the click, not present at baseline). The marker color
# #123456 lives on the .item LEAF div (explicit size + bg -> certain to survive
# classify); the role=region wrapper may not be emitted as a distinct node, so the
# gate must not depend on it carrying the marker.
_PAGE = """<!doctype html><meta charset=utf-8><title>component-gate</title>
<style>
  body { margin: 0; font-family: sans-serif; }
  #panel { display: none; margin: 40px; width: 320px;
           background: rgb(33,33,40); color: rgb(240,240,240); padding: 16px; }
  #panel.open { display: block; }
  .item { height: 48px; background: #123456; margin-top: 12px; }   /* marker on a sized leaf */
</style>
<body>
  <button id=btn aria-expanded="false" aria-controls="panel">Open</button>
  <div id=panel role="region">
    <p id=lbl>Revealed label</p>
    <div class=item></div>
  </div>
  <script>
    const b = document.getElementById('btn'), p = document.getElementById('panel');
    b.addEventListener('click', () => {
      const open = p.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  </script>
</body>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = _PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    out = ROOT / "fixtures" / "component" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def _check(obj) -> bool:
    states = obj.get("states") or []
    comps = [s["component"] for s in states if s.get("component")]
    print("states:", len(states), "components:", len(comps))
    if not comps:
        print("GATE FAIL: no state produced a component (panel not revealed?)")
        return False
    # the component that carries the panel's known bg (parse_color -> format-robust)
    target = None
    for c in comps:
        if any(parse_color((n.get("colors") or {}).get("bg")) == PANEL_RGB for n in c["nodes"]):
            target = c
            break
    if target is None:
        print("GATE FAIL: no component carried the panel bg", PANEL_RGB)
        return False
    n_ids = {n["id"] for n in target["nodes"]}
    for n in target["nodes"]:
        if n["parent"] is not None and n["parent"] not in n_ids:
            print("GATE FAIL: dangling parent id", n["parent"], "not in", n_ids)
            return False
    if not any(n["parent"] is None and n.get("mount") for n in target["nodes"]):
        print("GATE FAIL: no root records a mount point")
        return False
    if target["n_nodes"] != len(target["nodes"]):
        print("GATE FAIL: n_nodes != len(nodes)")
        return False
    print("component ok: n_nodes=%d, carried bg=%s, parents resolve, root mounted"
          % (target["n_nodes"], PANEL_RGB))
    return True


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    obj = _run(base + "/")
    ok = bool(obj) and _check(obj)

    srv.shutdown()
    if ok:
        print("GATE PASS: revealed panel captured as a reproducible component "
              "(structure + colors + mount), parents resolve.")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Verify `web_tokens.parse_color` matches the gate's use**

Run: `cd scripts && python3 -c "from web_tokens import parse_color; print(parse_color('rgb(18, 52, 86)'), parse_color('#123456'), parse_color(None))"`
Expected: `(18, 52, 86) (18, 52, 86) None`. (Confirms `parse_color` handles spaced rgb, hex, and None — the gate relies on all three.)

- [ ] **Step 3: Ignore the gate's scratch output**

In `.gitignore`, add (next to the existing `fixtures/consent/_out.json` line):

```
fixtures/component/_out.json
```

- [ ] **Step 4: Run the gate (CONTROLLER runs this on host Bash with the sandbox disabled)**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/component/run_component.py`
Expected: `GATE PASS: revealed panel captured as a reproducible component ...` and exit code 0.
Requires host Chrome on the probe-runner CDP profile (port 9222); `web_states` auto-discovers it via `ensure_browser("auto")`. The implementer subagent CANNOT run this (no host Chrome / sandboxed) — it writes the file, runs Steps 2–3, and reports DONE_WITH_CONCERNS noting the live gate is controller-run.

- [ ] **Step 5: Commit**

```bash
git add fixtures/component/run_component.py .gitignore
git commit -m "test: add component host gate (revealed panel -> reproducible component)"
```

---

### Task 8 (CONTROLLER, post-gate): results record + CONTEXT.md note

NOT a subagent task. After the host gate is green, the controller appends the results record (it documents host-gate outcomes the subagents never see), mirroring the `§C9-R-P3-G6` precedent.

- [ ] **Step 1: Append `§C9-R-P4` to `docs/plans/probe-runner-engine-capture-gaps.md`**

A new `## §C9-R-P4 — Results: per-state component capture LANDED` section covering: what it does (revealed subtree → re-rooted component on `states.json`, additive `component` key, schema unchanged); the reuse story (after-snapshot + `_node_colors` sidecar, no extra CDP trip); the honest ceilings (modal-collapse→mount.colors, closed-root/OOPIF, single-snapshot-no-timeline); the firewall line (same content-free fields as skeleton/tokens; pinned by `test_audit_passes_states_with_component`); and the verification (full unit count + `GATE PASS` summary). Repoint the `§C9 ladder status` line to note P4 landed.

- [ ] **Step 2: Append one sentence to the CONTEXT.md State glossary entry**

Tie the State entry to "a driven state now carries its revealed subtree as a content-free `component` (re-rooted skeleton + colors + mount), not just an appeared count."

- [ ] **Step 3: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md CONTEXT.md
git commit -m "docs: record per-state component capture (C9-R-P4) landed"
```

---

## Self-Review

**1. Spec coverage:**
- `_matches_rest` extraction → Task 1. ✓
- `build_component` (None, re-root, mount, colors, font, multi-root, modal-collapse) → Tasks 2–4. ✓
- Fork B (reuse `_node_colors`/font) → Tasks 2–3. ✓
- Fork C (additive `component`, schema unchanged) → Task 5. ✓
- Fork D (G4 states only — REST/consent untouched) → no task touches REST capture or the `consent` key. ✓
- Fork E (reuse after-snapshot) → Task 5 reuses the existing `after` in the loop; no new snapshot. ✓
- n_nodes==n_appeared invariant → Task 4. ✓
- Firewall content-free → Task 6 (real `cf.audit_bundle` on a states.json carrying a component). ✓
- Honest ceilings → Task 4 (modal-collapse) pinned; closed-root/OOPIF + single-snapshot inherited and documented in Task 8. ✓
- Docs record → Task 8. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. The one "<<KEEP THE EXISTING DOCSTRING UNCHANGED>>" marker (Task 1 Step 3) is an explicit instruction to preserve existing text, not a placeholder for new content. ✓

**3. Type / API consistency:**
- `_matches_rest(a, rest_nodes, radius)` — same signature in Task 1 (def) and Task 2 (`build_component` caller). ✓
- `build_component(rest, after, radius=24.0)` — same name in `_states.py` (Task 2), the import (Tasks 1-note/2), and `web_states.py` (Task 5). ✓
- component node keys `{id, role, bbox, z, sizing, layout, colors, parent, mount, font?}` — consistent across Tasks 2–4/6 and the implementation. ✓
- `_node_colors` keyed by `str(id)` — consistent with `_snapshot_skeleton`/`bundle_writer` (string keys) and the `_colors(node_id)` lookup. ✓
- Firewall API: `cf.audit_bundle(bundle_dir)` returns a violations list (`[]` == clean) — verified against `content_firewall.py:142` and the existing `_clean_bundle` test pattern. Task 6 uses it correctly (NOT a nonexistent `bw.audit_bundle(dict)`). ✓
- `web_tokens.parse_color` returns an `(r,g,b)` tuple or None — verified against `web_tokens.py`; Task 7 Step 2 re-confirms before the live run. ✓
- summary field `components_built` — defined once (Task 5). ✓
