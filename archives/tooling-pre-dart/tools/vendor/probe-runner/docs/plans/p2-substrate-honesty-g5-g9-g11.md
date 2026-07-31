# P2 — Substrate Honesty (G5 / G9 / G11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the capture engine HONESTLY label render-substrate regions whose visual content cannot be reproduced from the DOM — `<canvas>`/WebGL (G5), `<video>` (G9), and cross-SITE out-of-process iframes (G11) — by emitting a content-free `substrate.json` manifest in every bundle, so a consumer can tell an un-reproducible region from a reproducible empty box.

**Architecture:** Mirror the G4 pattern exactly. A pure, unit-tested core (`_substrate.py`) classifies a substrate region by element tag (+ for iframes, whether the snapshot captured its document). `web_skeleton.parse_snapshot` computes the marker per node from the live DOMSnapshot and `to_skeleton` attaches it. `bundle_writer` derives the manifest (free, from the skeleton nodes) and always writes `substrate.json`, which the content firewall audits like every other artifact. This is NOT a DOM "fix" — the pixels stay IP-blocked by the firewall; we only LABEL the boundary and degrade gracefully.

**Tech Stack:** Python 3 (stdlib only), pytest, Chrome DevTools Protocol (`DOMSnapshot.captureSnapshot`). Host gate uses a local two-port HTTP server.

---

## Empirical grounding (READ FIRST — the rule is observed, not assumed)

A host probe (`fixtures/substrate/probe_signal.py`, deleted in Task 5) ran a real DOMSnapshot over `fixtures/substrate/parent.html` served on port A with iframe children. Observed 2026-05-30, twice (JS-injected and static-template), identically:

| iframe | src | document captured? | `contentDocumentIndex` |
|--------|-----|--------------------|------------------------|
| `#so` same-origin | `child.html` (port A) | YES (in `documents`) | **present** |
| `#xo` same-SITE cross-ORIGIN | `http://127.0.0.1:B/child.html` | YES (in `documents`) | **present** |
| `#xs` cross-SITE | `http://localhost:B/child.html` | NO (absent from `documents`) | **absent** |

Conclusions that drive the design:
1. **The discriminator is `contentDocumentIndex` presence, NOT origin.** Same-site cross-origin iframes share the renderer process and ARE captured (reproducible). Only cross-SITE iframes go out-of-process (OOPIF) and are opaque. This CORRECTS the §C8/G11 "cross-origin" framing (recorded in Task 6).
2. **`localhost` vs `127.0.0.1` is a deterministic, offline cross-SITE pair** (different registrable name → OOPIF). The host gate uses it — no network, no Chrome relaunch.
3. **`contentDocumentIndex` is doc-local, node-indexed sparse data** (`{"index":[nodeIdx...], "value":[docIdx...]}`). Compute the captured-frame set INSIDE `parse_snapshot`'s per-document loop and key it by that doc's node index (= `dom_index`). This avoids the cross-document `dom_index` aliasing trap.
4. `canvas`/`video` are certain TAG reads (no probe needed). 2D-vs-WebGL is NOT distinguished (a `getContext` probe is destructive and does not change the reproducibility verdict — both are un-reproducible). Documented as a non-goal in Task 6.

## Execution notes (controller ↔ subagent split — same as the G4 plan)

- **Subagents do PURE work only** (Python edits + `pytest`). They MUST NOT run any CDP/host-Chrome command — those stall. The host gate (Task 5) is AUTHORED by a subagent but RUN by the controller on the host with `dangerouslyDisableSandbox: true`.
- **Every commit is GREEN.** There are no red commits (they stall the subagent review loop). Each task writes the failing test AND the implementation, runs the suite to confirm GREEN, then commits.
- **Git discipline (MANDATORY):** commit messages are a SINGLE line, NO `Co-Authored-By`/author trailer. Stage files EXPLICITLY by path (never `git add -A`/`git add .`). Commit only the files the task names.
- Run the full unit suite with: `cd scripts && python3 -m pytest -q` (macOS has no `timeout`; do not wrap it).

## File structure

- **Create** `scripts/_substrate.py` — pure core: `classify_substrate(tag, captured=None)` + `collect_substrate(nodes, url=None)`. No browser, no I/O.
- **Create** `scripts/test_substrate.py` — unit tests for the pure core.
- **Modify** `scripts/web_skeleton.py` — import `classify_substrate`; `parse_snapshot` computes a per-doc captured-frame set and attaches `rec["substrate"]`; `to_skeleton` copies it onto the node when truthy. NO skeleton schema bump (additive field; `probe-skeleton/2` stays).
- **Modify** `scripts/test_web_skeleton.py` — add a parse+to_skeleton test over a synthetic snapshot with canvas/video/captured-iframe/uncaptured-iframe nodes.
- **Modify** `scripts/bundle_writer.py` — `import _substrate`; `assemble` always derives `bundle["substrate"]`; `write_bundle` always writes `substrate.json`.
- **Modify** `scripts/test_bundle_writer.py` — update the default-keys assertion (now includes `substrate`); add a substrate-emitted + firewall-pass test.
- **Reuse** `fixtures/substrate/parent.html` + `fixtures/substrate/child.html` (already created); **create** `fixtures/substrate/run_substrate.py` (host gate); **delete** `fixtures/substrate/probe_signal.py` (throwaway).
- **Modify** `docs/plans/probe-runner-engine-capture-gaps.md` — append the §C9-R P2 result + correct the G11 framing.

---

### Task 1: Pure core — `classify_substrate`

**Files:**
- Create: `scripts/_substrate.py`
- Test: `scripts/test_substrate.py`

- [ ] **Step 1: Write `scripts/_substrate.py`**

```python
#!/usr/bin/env python3
"""_substrate — pure core for P2 substrate-honesty (G5/G9/G11). No browser/IO.

`classify_substrate`: map an element TAG (+ for iframes, whether its document was
captured in the snapshot) to the kind of UN-REPRODUCIBLE render substrate it is,
or None. `collect_substrate`: build the content-free substrate manifest from
skeleton nodes that carry a `substrate` marker. Both deterministic + unit-tested;
web_skeleton sets the per-node marker, bundle_writer derives the manifest.

WHY (honesty, not a DOM "fix"): a <canvas>/WebGL surface (G5), a <video> (G9), and
a cross-SITE out-of-process iframe (G11) paint pixels that are NOT in the DOM.
DOMSnapshot captures their BOX but never their content, and the firewall blocks the
pixels by construction (third-party IP). The honest output LABELS these regions so
a consumer knows they are un-reproducible from the bundle, instead of silently
emitting an empty box that looks reproducible.

G11 discriminator (empirically grounded 2026-05-30): whether the iframe's document
was CAPTURED (contentDocumentIndex present), NOT origin. Same-site cross-origin
iframes share the renderer process and ARE captured (reproducible); only cross-SITE
iframes go out-of-process (OOPIF) and are opaque. (127.0.0.1:A parent + 127.0.0.1:B
child = same-site cross-origin -> captured; localhost:B child = cross-site -> NOT
captured.) 2D-vs-WebGL canvas is intentionally NOT distinguished: the only probe
(getContext) is destructive and does not change the verdict — both are un-reproducible."""
from __future__ import annotations

_FRAME_TAGS = {"IFRAME", "FRAME"}


def classify_substrate(tag, captured=None):
    """Return the un-reproducible substrate kind for an element, or None.

    tag: the element's tag name (any case).
    captured: for frame tags, True/None when the frame's document WAS captured in
      the snapshot (reproducible -> not flagged), False when it was NOT captured
      (out-of-process / cross-site -> opaque). Ignored for non-frame tags.

    Kinds: 'canvas' (G5), 'video' (G9), 'iframe_uncaptured' (G11). Fires ONLY on
    CANVAS / VIDEO / un-captured IFRAME|FRAME — never IMG/PICTURE/SOURCE/SVG, which
    are ordinary swappable image slots reproducible from a slot."""
    t = (tag or "").upper()
    if t == "CANVAS":
        return "canvas"
    if t == "VIDEO":
        return "video"
    if t in _FRAME_TAGS:
        if captured is False:
            return "iframe_uncaptured"
        return None
    return None
```

- [ ] **Step 2: Write `scripts/test_substrate.py`**

```python
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _substrate import classify_substrate


def test_canvas_is_substrate():
    assert classify_substrate("CANVAS") == "canvas"
    assert classify_substrate("canvas") == "canvas"  # case-insensitive


def test_video_is_substrate():
    assert classify_substrate("VIDEO") == "video"


def test_captured_iframe_is_not_flagged():
    # document captured (same-origin OR same-site cross-origin) -> reproducible.
    assert classify_substrate("IFRAME", captured=True) is None
    assert classify_substrate("FRAME", captured=True) is None


def test_uncaptured_iframe_is_flagged():
    # cross-SITE OOPIF: document NOT in the snapshot -> opaque.
    assert classify_substrate("IFRAME", captured=False) == "iframe_uncaptured"
    assert classify_substrate("FRAME", captured=False) == "iframe_uncaptured"


def test_iframe_without_capture_signal_is_not_flagged():
    # default/None (no signal) errs toward reproducible — never over-flag.
    assert classify_substrate("IFRAME") is None
    assert classify_substrate("IFRAME", captured=None) is None


def test_plain_image_tags_are_never_substrate():
    # IMG/PICTURE/SOURCE/SVG are swappable slots, reproducible — not substrate.
    for t in ("IMG", "PICTURE", "SOURCE", "SVG", "DIV", "H1", ""):
        assert classify_substrate(t) is None
        assert classify_substrate(t, captured=False) is None
```

- [ ] **Step 3: Run the suite — confirm GREEN**

Run: `cd scripts && python3 -m pytest test_substrate.py -q`
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/_substrate.py scripts/test_substrate.py
git commit -m "feat(_substrate): add substrate classification core for G5/G9/G11 honesty"
```

---

### Task 2: Pure core — `collect_substrate` manifest builder

**Files:**
- Modify: `scripts/_substrate.py`
- Test: `scripts/test_substrate.py`

- [ ] **Step 1: Append `collect_substrate` to `scripts/_substrate.py`**

```python
def collect_substrate(nodes, url=None):
    """Build the content-free substrate manifest from skeleton nodes. Each node
    carrying a truthy `substrate` marker becomes one region descriptor
    (node_id/kind/role/bbox/z — geometry + mechanism only, no content). Returns
    {schema, url, regions, n_regions, kinds}; `kinds` is a per-kind count. Always
    well-formed (empty regions list when there is no substrate)."""
    regions = []
    for n in nodes:
        kind = n.get("substrate")
        if not kind:
            continue
        regions.append({"node_id": n.get("id"), "kind": kind,
                        "role": n.get("role"), "bbox": n.get("bbox"),
                        "z": n.get("z", 0)})
    kinds = {}
    for r in regions:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    return {"schema": "probe-substrate/1", "url": url,
            "regions": regions, "n_regions": len(regions), "kinds": kinds}
```

- [ ] **Step 2: Append tests to `scripts/test_substrate.py`**

```python
from _substrate import collect_substrate


def _node(nid, role, kind=None, x=0, y=0, w=10, h=10, z=0):
    n = {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z}
    if kind is not None:
        n["substrate"] = kind
    return n


def test_collect_builds_regions_and_kind_counts():
    nodes = [
        _node(0, "box"),                              # no substrate -> skipped
        _node(1, "image", kind="canvas", z=3),
        _node(2, "image", kind="video"),
        _node(3, "unknown_box", kind="iframe_uncaptured"),
        _node(4, "image"),                            # plain image -> skipped
    ]
    m = collect_substrate(nodes, url="http://x/")
    assert m["schema"] == "probe-substrate/1"
    assert m["url"] == "http://x/"
    assert m["n_regions"] == 3
    assert m["kinds"] == {"canvas": 1, "video": 1, "iframe_uncaptured": 1}
    canvas = next(r for r in m["regions"] if r["kind"] == "canvas")
    assert canvas == {"node_id": 1, "kind": "canvas",
                      "role": "image", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}, "z": 3}


def test_collect_is_content_free():
    # a region descriptor must carry ONLY geometry/mechanism keys, never content.
    m = collect_substrate([_node(0, "image", kind="canvas")])
    assert set(m["regions"][0].keys()) == {"node_id", "kind", "role", "bbox", "z"}


def test_collect_empty_when_no_substrate():
    m = collect_substrate([_node(0, "box"), _node(1, "text")])
    assert m["n_regions"] == 0 and m["regions"] == [] and m["kinds"] == {}
```

- [ ] **Step 3: Run the suite — confirm GREEN**

Run: `cd scripts && python3 -m pytest test_substrate.py -q`
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/_substrate.py scripts/test_substrate.py
git commit -m "feat(_substrate): add collect_substrate content-free manifest builder"
```

---

### Task 3: `web_skeleton` — attach the per-node substrate marker

**Files:**
- Modify: `scripts/web_skeleton.py` (import; `parse_snapshot`; `to_skeleton`)
- Test: `scripts/test_web_skeleton.py`

**Context:** `parse_snapshot` flattens `snap["documents"]` into records. `contentDocumentIndex` lives on each doc's `nodes` as `{"index":[nodeIdx...], "value":[docIdx...]}` and is node-indexed — so build the captured-frame set per document and key it by `dom_index` (which IS that doc's node index). The synthetic snaps in existing tests do NOT set `contentDocumentIndex`, so the lookup MUST default to empty (`.get(...) or {}`). `to_skeleton` only emits nodes whose bbox has w>0 and h>0, so a 0-size canvas correctly gets no marker.

- [ ] **Step 1: Add the failing test to `scripts/test_web_skeleton.py`**

Append (the helper `_idx` already exists at module top; reuse it):

```python
def _substrate_snap():
    # canvas, video, captured-iframe (#so/#xo), uncaptured-iframe (#xs), plain img.
    S = ["", "CANVAS", "VIDEO", "IFRAME", "IMG", "rgba(0,0,0,0)", "none",
         "0px", "block", "visible", "static", "rgb(0,0,0)", "left",
         "sans-serif", "border-box", "row", "0", "auto", "normal", "stretch"]
    names = [_idx(S, t) for t in ("CANVAS", "VIDEO", "IFRAME", "IFRAME", "IMG")]
    nodes = {"nodeName": names, "nodeValue": [-1] * 5, "parentIndex": [-1, 0, 0, 0, 0],
             # node 2 (first IFRAME) HAS a captured doc; node 3 (second IFRAME) does NOT.
             "contentDocumentIndex": {"index": [2], "value": [1]}}

    def row():
        d = {}
        for k in ws.WANT_STYLES:
            if k == "display": d[k] = _idx(S, "block")
            elif k == "visibility": d[k] = _idx(S, "visible")
            elif k == "position": d[k] = _idx(S, "static")
            elif k in ("color", "background-color"): d[k] = _idx(S, "rgba(0,0,0)")
            elif k == "text-align": d[k] = _idx(S, "left")
            elif k == "font-family": d[k] = _idx(S, "sans-serif")
            elif k == "box-sizing": d[k] = _idx(S, "border-box")
            elif k == "flex-direction": d[k] = _idx(S, "row")
            elif k in ("flex-grow", "flex-shrink"): d[k] = _idx(S, "0")
            elif k in ("width", "height", "flex-basis", "min-width", "max-width"):
                d[k] = _idx(S, "auto")
            elif k == "align-items" or k == "justify-content": d[k] = _idx(S, "stretch")
            elif k == "align-self": d[k] = _idx(S, "normal")
            elif k in ("grid-template-columns", "grid-template-rows"): d[k] = _idx(S, "none")
            elif k == "background-image": d[k] = _idx(S, "none")
            else: d[k] = _idx(S, "0px")
        return [d[k] for k in ws.WANT_STYLES]

    layout = {
        "nodeIndex": [0, 1, 2, 3, 4],
        "bounds": [[0, 0, 200, 120], [0, 130, 200, 120], [0, 260, 200, 120],
                   [0, 390, 200, 120], [0, 520, 200, 120]],
        "paintOrders": [1, 2, 3, 4, 5],
        "text": [-1, -1, -1, -1, -1],
        "styles": [row(), row(), row(), row(), row()],
    }
    return {"strings": S, "documents": [{"nodes": nodes, "layout": layout}]}


def test_parse_attaches_substrate_marker():
    recs = ws.parse_snapshot(_substrate_snap(), ws.WANT_STYLES)
    by_tag_idx = {0: "canvas", 1: "video", 2: None, 3: "iframe_uncaptured", 4: None}
    for i, expected in by_tag_idx.items():
        assert recs[i].get("substrate") == expected, (i, recs[i].get("substrate"))


def test_to_skeleton_copies_substrate_onto_nodes():
    snap = _substrate_snap()
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES)
    sk, _ = ws.to_skeleton(recs, svg_set=set(),
                           parent_index=snap["documents"][0]["nodes"]["parentIndex"],
                           url="http://x/", viewport={"w": 200, "h": 120, "dpr": 1.0},
                           page={"w": 200, "h": 640})
    subs = {n["id"]: n.get("substrate") for n in sk["nodes"]}
    kinds = sorted(v for v in subs.values() if v)
    assert kinds == ["canvas", "iframe_uncaptured", "video"]
    # a captured iframe and a plain img carry NO substrate key.
    assert any("substrate" not in n for n in sk["nodes"])


def test_existing_snap_without_content_doc_index_has_no_substrate():
    # the legacy _snap() has no contentDocumentIndex -> parse must default cleanly
    # (no KeyError) and emit no substrate markers (DIV/H1/IMG are not substrate).
    recs = ws.parse_snapshot(_snap(), ws.WANT_STYLES)
    assert all(r.get("substrate") is None for r in recs)
```

- [ ] **Step 2: Run the new tests — confirm they FAIL (no commit)**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q -k substrate`
Expected: FAIL — `parse_snapshot` does not yet attach `substrate`.

- [ ] **Step 3: Edit `scripts/web_skeleton.py` — import**

Change the import line:

```python
from _web_eval import add_transport_args, navigate, resolve_web_eval
```

to add the substrate import directly beneath it:

```python
from _web_eval import add_transport_args, navigate, resolve_web_eval
from _substrate import classify_substrate
```

- [ ] **Step 4: Edit `parse_snapshot` — compute the captured-frame set and the marker**

Inside `parse_snapshot`, the per-document loop currently reads:

```python
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
```

Add the captured-frame set after `paints = ...` (it is doc-local, node-indexed):

```python
        paints = layout.get("paintOrders", [])
        # contentDocumentIndex is doc-local, node-indexed sparse data: its `index`
        # entries are the node indices of frame owners whose document WAS captured
        # in this snapshot. A frame node NOT in this set was not captured
        # (out-of-process / cross-site OOPIF) -> opaque substrate (G11). Default to
        # empty when absent (legacy/synthetic snapshots have no frames).
        captured_frames = set((nodes.get("contentDocumentIndex") or {}).get("index", []) or [])
```

Then in the record dict, after the existing `"text": s(ltext[i]) if i < len(ltext) else None,` line, add the substrate field (`dom_i` is this doc's node index, matching `captured_frames`):

```python
                "text": s(ltext[i]) if i < len(ltext) else None,
                "substrate": classify_substrate(
                    (s(names[dom_i]) or "").upper(),
                    captured=(dom_i in captured_frames)),
```

- [ ] **Step 5: Edit `to_skeleton` — copy the marker onto emitted nodes**

In `to_skeleton`, immediately after the `node = { ... }` literal is built (before the `if role == "text":` block), add:

```python
        if r.get("substrate"):
            node["substrate"] = r["substrate"]
```

- [ ] **Step 6: Run the full skeleton suite — confirm GREEN**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q`
Expected: all tests PASS (new substrate tests + all pre-existing tests, including `test_to_skeleton_locks_full_schema`, which uses `.issubset` and tolerates the additive key).

- [ ] **Step 7: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat(web_skeleton): attach per-node substrate marker (canvas/video/uncaptured-iframe)"
```

---

### Task 4: `bundle_writer` — always emit `substrate.json`

**Files:**
- Modify: `scripts/bundle_writer.py` (`import`; `assemble`; `write_bundle`)
- Test: `scripts/test_bundle_writer.py`

**Context:** `assemble` embeds the full skeleton and returns an in-memory bundle dict; `write_bundle` writes each artifact then runs `cf.audit_bundle` (raises `ContentLeak` on any leak — so a passing `write_bundle` IS the firewall gate). `redact_node` is a denylist (`CONTENT_KEYS`); a `substrate` node key survives redaction. The substrate manifest is DERIVED for free from the skeleton nodes, so unlike the opt-in `states`, it is ALWAYS present.

- [ ] **Step 1: Add the failing tests to `scripts/test_bundle_writer.py`**

First, find the existing test that asserts the default `assemble()` output key set (it currently expects the 5 keys `meta/skeleton/tokens/motion/manifest` and that `states` is absent). UPDATE that assertion so the expected default key set INCLUDES `substrate`:

```python
    # substrate is ALWAYS present (derived free from the skeleton); states is opt-in.
    assert set(bundle.keys()) == {"meta", "skeleton", "tokens", "motion", "manifest", "substrate"}
    assert "states" not in bundle
```

Then append a new test (adapt the existing assemble/write_bundle fixtures in this file for `skeleton`/`tokens`/`node_colors` shape — reuse whatever helper the other tests use to build a minimal skeleton; the key addition is nodes carrying a `substrate` marker):

```python
def test_write_bundle_emits_substrate_json_and_passes_audit(tmp_path):
    import json
    skeleton = {
        "schema": "probe-skeleton/2", "url": "http://x/",
        "viewport": {"w": 200, "h": 120, "dpr": 1.0}, "page": {"w": 200, "h": 640},
        "nodes": [
            {"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 200, "h": 40},
             "z": 0, "parent": None, "sizing": {"w": "fill", "h": "fixed", "confidence": "high"},
             "layout": {"mode": "block", "direction": "row", "gap": 0.0, "pad": [0, 0, 0, 0],
                        "justify": "normal", "align": "normal", "grid_cols": None, "grid_rows": None},
             "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None},
            {"id": 1, "role": "image", "bbox": {"x": 0, "y": 130, "w": 200, "h": 120},
             "z": 1, "parent": 0, "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
             "layout": {"mode": "block", "direction": "row", "gap": 0.0, "pad": [0, 0, 0, 0],
                        "justify": "normal", "align": "normal", "grid_cols": None, "grid_rows": None},
             "token_ref": {"bg": None, "fg": None, "border": None}, "anim_ref": None,
             "substrate": "canvas"},
        ],
    }
    tokens = {"palette": {}, "type": {}, "spacing": [], "radii": [], "shadows": []}
    bundle = bw.assemble(skeleton, tokens, node_colors={}, motion_rows=[], meta_extra={})
    assert bundle["substrate"]["schema"] == "probe-substrate/1"
    assert bundle["substrate"]["n_regions"] == 1
    assert bundle["substrate"]["kinds"] == {"canvas": 1}
    out = tmp_path / "bundle"
    bw.write_bundle(bundle, str(out))   # raises ContentLeak if the firewall finds content
    written = json.loads((out / "substrate.json").read_text())
    assert written["regions"][0]["kind"] == "canvas"
    assert set(written["regions"][0].keys()) == {"node_id", "kind", "role", "bbox", "z"}
```

(Use the module alias the test file already imports `bundle_writer` as — likely `bw` or `bundle_writer`. Match the file's existing convention.)

- [ ] **Step 2: Run the new tests — confirm they FAIL (no commit)**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: FAIL — `assemble` does not yet add `substrate`; `substrate.json` not written.

- [ ] **Step 3: Edit `scripts/bundle_writer.py` — import**

Beneath `import slots as _slots` add:

```python
import _substrate
```

- [ ] **Step 4: Edit `assemble` — derive the manifest (always)**

In `assemble`, after the line `manifest = _slots.build_slots(nodes)` and before `skeleton["nodes"] = [cf.redact_node(n) for n in nodes]`, add:

```python
    substrate = _substrate.collect_substrate(nodes, url=skeleton.get("url"))
```

Then in the `bundle = { ... }` literal, add `substrate` as an always-present key (alongside `manifest`):

```python
    bundle = {
        "meta": meta,
        "skeleton": skeleton,
        "tokens": tokens,
        "motion": motion,
        "manifest": manifest,
        "substrate": substrate,
    }
```

- [ ] **Step 5: Edit `write_bundle` — write `substrate.json` (always)**

In `write_bundle`, after the `assets/manifest.json` write and before the optional `states` block (so it is unconditional), add:

```python
    (root / "substrate.json").write_text(json.dumps(bundle["substrate"], indent=2))
```

- [ ] **Step 6: Run the full suite — confirm GREEN**

Run: `cd scripts && python3 -m pytest -q`
Expected: all tests PASS (updated key-set assertion + new substrate test + everything else).

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat(bundle_writer): always emit content-free substrate.json manifest"
```

---

### Task 5: Host gate — `run_substrate.py` (AUTHORED by subagent, RUN by controller)

**Files:**
- Create: `fixtures/substrate/run_substrate.py`
- Delete: `fixtures/substrate/probe_signal.py`
- (Reuse, already created: `fixtures/substrate/parent.html`, `fixtures/substrate/child.html`)

**Context:** The subagent ONLY writes `run_substrate.py` and deletes the throwaway probe — it MUST NOT run any CDP command. The controller runs the gate on the host. The gate fills the `parent.html` template into a tmp dir (same-site src = `http://127.0.0.1:B/child.html`, cross-site src = `http://localhost:B/child.html`), serves the tmp dir on ports A and B, runs `web_skeleton.py` → `web_tokens.py` → `bundle_writer.py`, then asserts the bundle's `substrate.json` flags canvas + video + the cross-site (`localhost`) iframe, and does NOT flag the same-origin / same-site-cross-origin iframes.

- [ ] **Step 1: Write `fixtures/substrate/run_substrate.py`**

```python
#!/usr/bin/env python3
"""Host gate (G5/G9/G11 substrate honesty): fills parent.html (same-site src =
127.0.0.1:B, cross-site src = localhost:B), serves it, runs the full
web_skeleton -> web_tokens -> bundle_writer pipeline, and asserts the bundle's
substrate.json flags canvas + video + the cross-SITE iframe ONLY (same-origin and
same-site-cross-origin iframes are captured -> NOT flagged). MUST run on the host
(host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT).

  python3 fixtures/substrate/run_substrate.py
"""
import http.server
import json
import os
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
OUT = "/tmp/substrate-gate"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def serve(directory, port):
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=directory, **k)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def ensure_chrome():
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "web_launch.py")],
                       capture_output=True, text=True)
    print("web_launch:", (r.stdout or "").strip()[:120], (r.stderr or "").strip()[:120])
    time.sleep(1.5)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=SCRIPTS, timeout=120)
    print("  $", " ".join(os.path.basename(c) for c in cmd[1:3]),
          "| exit", r.returncode, "|", (r.stderr or "").strip()[-160:])
    return r


def main():
    a, b = free_port(), free_port()
    tmp = tempfile.mkdtemp(prefix="substrate-gate-")
    shutil.copy(os.path.join(HERE, "child.html"), os.path.join(tmp, "child.html"))
    tpl = open(os.path.join(HERE, "parent.html")).read()
    filled = (tpl.replace("__SAMESITE_SRC__", "http://127.0.0.1:%d/child.html" % b)
                 .replace("__XSITE_SRC__", "http://localhost:%d/child.html" % b))
    open(os.path.join(tmp, "parent.html"), "w").write(filled)
    hA, hB = serve(tmp, a), serve(tmp, b)
    print("parent port:", a, "| child port:", b)
    ensure_chrome()
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    sk, tok = os.path.join(OUT, "skeleton.json"), os.path.join(OUT, "tokens.json")
    bundle = os.path.join(OUT, "bundle")
    url = "http://127.0.0.1:%d/parent.html" % a
    try:
        run([sys.executable, os.path.join(SCRIPTS, "web_skeleton.py"), "--url", url, "--out", sk])
        run([sys.executable, os.path.join(SCRIPTS, "web_tokens.py"), "--url", url, "--out", tok])
        run([sys.executable, os.path.join(SCRIPTS, "bundle_writer.py"),
             "--skeleton", sk, "--tokens", tok, "--out", bundle])
    finally:
        hA.server_close()
        hB.server_close()
        shutil.rmtree(tmp, ignore_errors=True)

    subp = os.path.join(bundle, "substrate.json")
    if not os.path.exists(subp):
        print("FAIL — no substrate.json (bundle_writer failed or firewall raised)")
        return 1
    man = json.loads(open(subp).read())
    kinds = man.get("kinds", {})
    print("substrate kinds:", kinds, "| n_regions:", man.get("n_regions"))
    # canvas (G5) + video (G9) + exactly ONE uncaptured iframe (G11, the localhost one).
    ok = (kinds.get("canvas", 0) >= 1 and kinds.get("video", 0) >= 1
          and kinds.get("iframe_uncaptured", 0) == 1)
    if ok:
        print("PASS — canvas+video flagged; cross-SITE iframe flagged; "
              "same-origin/same-site iframes NOT flagged (exactly 1 uncaptured)")
        return 0
    print("FAIL — expected canvas>=1, video>=1, iframe_uncaptured==1; got", kinds)
    return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Delete the throwaway probe**

```bash
git rm fixtures/substrate/probe_signal.py 2>/dev/null || rm -f fixtures/substrate/probe_signal.py
```

- [ ] **Step 3: Confirm the full unit suite is still GREEN (no CDP)**

Run: `cd scripts && python3 -m pytest -q`
Expected: all tests PASS.

- [ ] **Step 4: Commit (fixtures + gate; NOTE the controller runs the gate, not the subagent)**

```bash
git add fixtures/substrate/parent.html fixtures/substrate/child.html fixtures/substrate/run_substrate.py
git rm --cached fixtures/substrate/probe_signal.py 2>/dev/null || true
git commit -m "test(substrate): add G5/G9/G11 host gate + fixtures, drop throwaway probe"
```

**CONTROLLER STEP (NOT the subagent):** run the gate on the host —
`python3 fixtures/substrate/run_substrate.py` (with `dangerouslyDisableSandbox: true`).
Expected: `PASS — canvas+video flagged; cross-SITE iframe flagged ...` and substrate kinds `{"canvas": 1, "video": 1, "iframe_uncaptured": 1}`.

---

### Task 6: Document the result + correct the G11 framing

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md`

- [ ] **Step 1: Append a `§C9-R-P2` results section** recording, honestly:
  - **G5 canvas / G9 video — DONE (labeling):** `web_skeleton` now tags `<canvas>` (`substrate:"canvas"`) and `<video>` (`substrate:"video"`); `bundle_writer` surfaces them in `substrate.json`. This is HONEST LABELING, not pixel capture — the firewall blocks the pixels by construction, and an owned-content clip/canvas-capture is a documented NON-GOAL (ownership is unverifiable; literal third-party pixels are IP-blocked).
  - **G11 cross-site iframe — DONE (labeling) + FRAMING CORRECTED:** the real discriminator is `contentDocumentIndex` presence (document captured?), NOT origin. The §C8 "cross-origin iframe is opaque" wording is imprecise: same-site cross-origin iframes share the renderer process and ARE captured (reproducible). Only cross-SITE OOPIFs are opaque. Empirically grounded (probe, 2026-05-30): 127.0.0.1:A + 127.0.0.1:B child → captured; `localhost`:B child → not captured. Marker named `iframe_uncaptured` (honest about the mechanism — "document not in snapshot" — not the cause).
  - **Honest limits:** 2D-vs-WebGL canvas NOT distinguished (destructive `getContext`, verdict-irrelevant). A cross-site iframe NESTED inside a same-origin child is detected per-document, but a 0-size substrate element is not emitted (invisible → no marker). Same-origin/same-site embeds are correctly NOT flagged.
  - **Verification:** full unit suite green; host gate green (`{"canvas":1,"video":1,"iframe_uncaptured":1}`).

- [ ] **Step 2: Update the "Next on the §C9 ladder" line** at the end of §C9-R: P2 is now LANDED; next is **P3 — G1 settle (RSC-safe max-wait + network-idle) + G6 consent-dismiss.**

- [ ] **Step 3: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs(capture-gaps): record P2 substrate honesty (G5/G9/G11) landed; correct G11 cross-site framing"
```

---

## Final acceptance

- [ ] Full unit suite green: `cd scripts && python3 -m pytest -q`.
- [ ] **Controller** host gate green: `python3 fixtures/substrate/run_substrate.py` → `PASS`, kinds `{"canvas":1,"video":1,"iframe_uncaptured":1}`.
- [ ] `git status` clean; throwaway `probe_signal.py` gone.
- [ ] Final whole-implementation code review (subagent-driven-development's last step).

## Self-review (run after writing; fix inline)

**Spec coverage:** G5 canvas → `classify_substrate("CANVAS")`→`"canvas"` (Task 1) + skeleton marker (Task 3) + manifest (Task 4) + gate (Task 5). G9 video → same path. G11 cross-site iframe → `contentDocumentIndex`-absent → `"iframe_uncaptured"` (Tasks 1/3) + gate's `localhost` leg (Task 5). "behavior-class box + document the boundary, degrade gracefully" → labeling + §C9-R-P2 + owned-clip non-goal (Task 6). All §C9 P2 requirements mapped.

**Placeholder scan:** every code/test step has complete code; every run step has an exact command + expected result. No TBD/“similar to”.

**Type consistency:** `classify_substrate(tag, captured=None)→str|None`; `collect_substrate(nodes, url=None)→{schema,url,regions,n_regions,kinds}`; region keys exactly `{node_id,kind,role,bbox,z}`; node marker key `substrate`; manifest schema `probe-substrate/1`; skeleton schema unchanged `probe-skeleton/2`. Names used identically across Tasks 1–6.
