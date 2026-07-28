# Regime 3a — Theme/Preference Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture, as an additive per-node `theme` sidecar, the resolved CSS style DELTA each element takes under `prefers-color-scheme:dark` / `forced-colors:active` / `prefers-contrast:more`, joined by `backendNodeId`, redacted content-free.

**Architecture:** Pin base media → capture base skeleton → for each condition, `Emulation.setEmulatedMedia` + recapture + diff full resolved styles vs base over a fixed prop universe → store changed props inline, keyed by `backendNodeId` re-keyed to skeleton node id. Pure diff core in a new `_theme.py`; CDP recapture orchestration in `web_skeleton.py`; redaction reuses `_style.redact_style_value` (+ `content` routing); `bundle_writer.apply_node_theme` mirrors `apply_node_pseudo`; firewall unchanged.

**Tech Stack:** Python 3.13, pytest, Chrome DevTools Protocol (`DOMSnapshot.captureSnapshot`, `Emulation.setEmulatedMedia`), `websocket-client`.

**Spec:** `docs/plans/regime3a-theme-preference-capture-design.md`. Read §1 (the `backendNodeId` join, probe-verified), §3 (base-media pinning + phantom-diff guard), §9 (ceilings).

**Conventions (from this repo, MANDATORY):**
- Commits SINGLE-LINE, no body, no trailers, no `Co-Authored-By`.
- Stage files EXPLICITLY by path. NEVER `git add -A`/`git add .`.
- ONE commit per task; a review-driven fix is its own commit.
- Do NOT push — all work local on master.
- Run tests: `cd scripts && python3 -m pytest <file> -v`.
- `backendNodeId` is internal — NEVER written to disk.

---

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `scripts/_theme.py` (new) | Pure diff core: `styles_by_backend`, `diff_theme`, `rekey_by_node_id`, `build_node_theme`. No browser, no I/O. | 3 |
| `scripts/test_theme.py` (new) | Unit tests for `_theme`. | 3 |
| `scripts/web_skeleton.py` | `parse_snapshot` extracts `backend`; `to_skeleton` returns `node_backend`; `THEME_PROPS`/`BASE_FEATURES`/`CONDITION_OVERRIDE`; `_styles_by_backend`, `capture_with_themes`; `_snapshot_skeleton`/`_capture_one` thread `node_backend`; `--themes` flag. | 1,2,7 |
| `scripts/_style.py` | `redact_theme` (mirror `redact_pseudo`). | 4 |
| `scripts/bundle_writer.py` | `apply_node_theme`; thread through `assemble`/`main`; pop `_node_theme` + discard `_node_backend`. | 5 |
| `scripts/test_web_skeleton.py` | `parse_snapshot` backend test; `to_skeleton` 5-tuple migration + `node_backend` test. | 1,2 |
| `scripts/test_style.py` | `redact_theme` tests. | 4 |
| `scripts/test_bundle_writer.py` | `apply_node_theme` round-trip tests. | 5 |
| `scripts/test_content_firewall.py` | theme-delta clean + un-redacted-url canary. | 6 |
| `fixtures/theme/run_theme.py` (new) | Host CDP gate — proves join correctness end to end. | 8 (controller runs) |
| `scripts/web_states.py` | Migrate one `_snapshot_skeleton` unpack to 4-value. | 7 |

---

## Task 1: `parse_snapshot` extracts `backendNodeId` per record

**Files:**
- Modify: `scripts/web_skeleton.py` (`parse_snapshot`, ~line 194 and the record dict ~line 222)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_web_skeleton.py`:

```python
def test_parse_extracts_backend_node_id():
    snap = _snap()
    snap["documents"][0]["nodes"]["backendNodeId"] = [101, 102, 103]
    recs = ws.parse_snapshot(snap, WANT)
    assert [r["backend"] for r in recs] == [101, 102, 103]


def test_parse_backend_absent_is_none():
    # legacy/synthetic snaps without backendNodeId -> backend None, no crash
    recs = ws.parse_snapshot(_snap(), WANT)
    assert all(r["backend"] is None for r in recs)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_parse_extracts_backend_node_id -v`
Expected: FAIL with `KeyError: 'backend'`.

- [ ] **Step 3: Implement**

In `web_skeleton.py` `parse_snapshot`, inside the `for doc in snap["documents"]:` loop, alongside `names = nodes["nodeName"]` (~line 194), add:

```python
        backend = nodes.get("backendNodeId") or []
```

Then in the record dict appended in the `for i, dom_i in enumerate(li_node):` loop (after the `"pseudo": pseudo_by_node.get(dom_i),` line ~222), add:

```python
                "backend": backend[dom_i] if dom_i < len(backend) else None,
```

- [ ] **Step 4: Run tests**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -v`
Expected: new tests PASS; all pre-existing `parse_snapshot` tests still PASS (they don't assert `backend`).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: parse backendNodeId per record in parse_snapshot"
```

---

## Task 2: `to_skeleton` returns `node_backend` (4→5-tuple) + migrate unpack sites

**Files:**
- Modify: `scripts/web_skeleton.py` (`to_skeleton` ~384-475; `_snapshot_skeleton` unpack ~563)
- Test: `scripts/test_web_skeleton.py` (4 existing `to_skeleton` unpack sites + new test)

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_web_skeleton.py`:

```python
def test_to_skeleton_returns_node_backend_map():
    snap = _snap()
    snap["documents"][0]["nodes"]["backendNodeId"] = [101, 102, 103]
    recs = ws.parse_snapshot(snap, WANT)
    svg_set = ws.svg_descendants(snap["documents"][0], snap["strings"])
    result = ws.to_skeleton(recs, svg_set, parent_index=[-1, 0, 0], url="u",
                            viewport={"w": 1440, "h": 900, "dpr": 1},
                            page={"w": 1440, "h": 35137})
    assert len(result) == 5  # skeleton, node_colors, node_style, node_pseudo, node_backend
    sk, _, _, _, node_backend = result
    # every emitted node id maps to a backendNodeId drawn from [101,102,103]
    for n in sk["nodes"]:
        assert node_backend[n["id"]] in (101, 102, 103)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_to_skeleton_returns_node_backend_map -v`
Expected: FAIL — `to_skeleton` returns a 4-tuple (`len(result) == 4`).

- [ ] **Step 3: Implement**

In `web_skeleton.py` `to_skeleton`:

1. Initialize the map next to the other accumulators (near `node_colors = {}` / `node_style = {}` at the top of the function):

```python
    node_backend = {}
```

2. In the first record loop, immediately after `emitted.append(node)` is NOT where ids are stable — set it right after the `node` dict is created and before `emitted.append(node)`. Locate the block that sets `node_colors[node["id"]] = {...}` (~line 433) and add directly after it:

```python
        node_backend[node["id"]] = r.get("backend")
```

3. Change the return statement (~line 475) from:

```python
    return skeleton, node_colors, node_style, node_pseudo
```

to:

```python
    return skeleton, node_colors, node_style, node_pseudo, node_backend
```

4. Update the docstring's "Returns (skeleton, node_colors, node_style, node_pseudo)" to add `, node_backend` and one line: `node_backend is {node_id: backendNodeId} — the stable cross-capture join key (internal; never written to disk).`

5. Migrate the production unpack in `_snapshot_skeleton` (~line 563) from:

```python
    sk, node_colors, node_style, node_pseudo = to_skeleton(
```

to:

```python
    sk, node_colors, node_style, node_pseudo, node_backend = to_skeleton(
```

(Leave `node_backend` unused here for now; Task 7 threads it out.)

6. Migrate the 4 existing test unpack sites in `test_web_skeleton.py` (lines ~228, ~263, ~373, and any other `ws.to_skeleton(` call) from 4-value to 5-value by appending one `_`. E.g. `sk, node_colors, _, _ = ws.to_skeleton(...)` → `sk, node_colors, _, _, _ = ws.to_skeleton(...)`; `sk, _, _, _ = ws.to_skeleton(...)` → `sk, _, _, _, _ = ws.to_skeleton(...)`.

- [ ] **Step 4: Run tests**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -v`
Expected: ALL pass (new test + migrated unpack sites).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: return node_backend join map from to_skeleton"
```

---

## Task 3: `_theme.py` — pure diff core

**Files:**
- Create: `scripts/_theme.py`
- Test: `scripts/test_theme.py` (new)

- [ ] **Step 1: Write the failing test**

Create `scripts/test_theme.py`:

```python
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _theme  # noqa: E402

U = ["color", "background-color", "box-shadow"]


def test_styles_by_backend_skips_pseudo_and_none_backend():
    recs = [
        {"backend": 10, "pseudo": None, "style": {"color": "rgb(0,0,0)"}},
        {"backend": 11, "pseudo": "before", "style": {"color": "rgb(9,9,9)"}},
        {"backend": None, "pseudo": None, "style": {"color": "rgb(1,1,1)"}},
    ]
    assert _theme.styles_by_backend(recs) == {10: {"color": "rgb(0,0,0)"}}


def test_diff_theme_emits_only_changed_props():
    base = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(255,255,255)",
                 "box-shadow": "none"}}
    cond = {10: {"color": "rgb(255,255,255)", "background-color": "rgb(255,255,255)",
                 "box-shadow": "none"}}
    assert _theme.diff_theme(base, cond, U) == {10: {"color": "rgb(255,255,255)"}}


def test_diff_theme_catches_both_directions():
    # none -> value (appeared) AND value -> none (reset)
    base = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                 "box-shadow": "none"}}
    cond = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                 "box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    assert _theme.diff_theme(base, cond, U) == {10: {"box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    base2 = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                  "box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    cond2 = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                  "box-shadow": "none"}}
    assert _theme.diff_theme(base2, cond2, U) == {10: {"box-shadow": "none"}}


def test_diff_theme_drops_node_absent_in_condition():
    base = {10: {"color": "rgb(0,0,0)"}, 11: {"color": "rgb(0,0,0)"}}
    cond = {10: {"color": "rgb(9,9,9)"}}  # node 11 went display:none -> absent
    assert _theme.diff_theme(base, cond, U) == {10: {"color": "rgb(9,9,9)"}}


def test_diff_theme_no_change_emits_nothing():
    base = {10: {"color": "rgb(0,0,0)"}}
    cond = {10: {"color": "rgb(0,0,0)"}}
    assert _theme.diff_theme(base, cond, U) == {}


def test_rekey_by_node_id_maps_backend_to_node():
    delta = {101: {"color": "rgb(9,9,9)"}, 999: {"color": "rgb(1,1,1)"}}
    node_backend = {0: 101, 1: 102}  # backend 999 has no node -> dropped
    assert _theme.rekey_by_node_id(delta, node_backend) == {0: {"color": "rgb(9,9,9)"}}


def test_build_node_theme_transposes_label_to_node_keyed():
    per_condition = {
        "dark": {0: {"color": "rgb(255,255,255)"}},
        "contrast": {0: {"color": "rgb(0,0,0)"}, 1: {"color": "rgb(0,0,0)"}},
    }
    out = _theme.build_node_theme(per_condition)
    assert out == {
        0: {"dark": {"color": "rgb(255,255,255)"}, "contrast": {"color": "rgb(0,0,0)"}},
        1: {"contrast": {"color": "rgb(0,0,0)"}},
    }


def test_build_node_theme_skips_empty_delta():
    assert _theme.build_node_theme({"dark": {0: {}}}) == {}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_theme.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named '_theme'`.

- [ ] **Step 3: Implement**

Create `scripts/_theme.py`:

```python
#!/usr/bin/env python3
"""_theme — pure core for Regime-3a theme/preference style-delta capture (no
browser, no I/O). web_skeleton wraps these with CDP Emulation.setEmulatedMedia
recapture. The join key is backendNodeId (DOMSnapshot-stable across a base->
condition recapture; verified, design §1) — NOT the positional skeleton id.
Deterministic; unit-tested. Content-free: emits raw resolved values that
bundle_writer redacts via _style.redact_theme before disk."""


def styles_by_backend(recs):
    """Map backendNodeId -> full resolved style dict, for ELEMENT records only
    (skip pseudo-element records and records with no backendNodeId). recs is
    web_skeleton.parse_snapshot output."""
    out = {}
    for r in recs:
        if r.get("pseudo"):
            continue
        b = r.get("backend")
        if b is None:
            continue
        out[b] = r.get("style") or {}
    return out


def diff_theme(base_by_backend, cond_by_backend, universe):
    """Return {backendNodeId: {prop: cond_value}} for every node present in BOTH
    base and the condition where a prop in `universe` differs. A node absent from
    the condition capture (display:none under the condition, or a theme-triggered
    DOM mutation) is DROPPED — never reattached (style-only ceiling, design §9).
    computedStyles resolves every requested prop for a laid-out node, so both raw
    maps carry every prop; the compare is a plain `base != cond`, which catches
    both directions (a reset is just a value change). Emits nothing for a node
    with no changed prop."""
    out = {}
    for b, base_style in base_by_backend.items():
        cond_style = cond_by_backend.get(b)
        if cond_style is None:
            continue
        delta = {}
        for prop in universe:
            if base_style.get(prop) != cond_style.get(prop):
                delta[prop] = cond_style.get(prop)
        if delta:
            out[b] = delta
    return out


def rekey_by_node_id(delta_by_backend, node_backend):
    """Re-key {backendNodeId: delta} -> {node_id: delta} via node_backend
    ({node_id: backendNodeId}). A backendNodeId with no matching node_id is
    dropped (defensive)."""
    backend_to_id = {b: nid for nid, b in node_backend.items()}
    out = {}
    for b, delta in delta_by_backend.items():
        nid = backend_to_id.get(b)
        if nid is not None:
            out[nid] = delta
    return out


def build_node_theme(per_condition):
    """Transpose {condition_label: {node_id: delta}} -> {node_id: {label: delta}},
    keeping only non-empty deltas. The on-disk _node_theme sidecar shape."""
    out = {}
    for label, by_node in per_condition.items():
        for nid, delta in by_node.items():
            if delta:
                out.setdefault(nid, {})[label] = delta
    return out
```

- [ ] **Step 4: Run tests**

Run: `cd scripts && python3 -m pytest test_theme.py -v`
Expected: all 8 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/_theme.py scripts/test_theme.py
git commit -m "feat: add _theme pure diff core for theme/preference deltas"
```

---

## Task 4: `_style.redact_theme`

**Files:**
- Modify: `scripts/_style.py` (after `redact_pseudo`)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_style.py` (extend the existing import line if needed):

```python
from _style import redact_theme  # noqa: E402


def test_redact_theme_redacts_box_url_keeps_rgb():
    themes = {"dark": {"color": "rgb(240, 240, 240)",
                       "background-image": 'url("https://a/b.png")'},
              "contrast": {"color": "rgb(0, 0, 0)"}}
    out = redact_theme(themes)
    assert out["dark"]["color"] == "rgb(240, 240, 240)"          # raw rgb kept
    assert out["dark"]["background-image"] == 'url("<asset>")'    # external url redacted
    assert out["contrast"]["color"] == "rgb(0, 0, 0)"


def test_redact_theme_keeps_same_doc_fragment_url():
    out = redact_theme({"dark": {"clip-path": "url(#c)"}})
    assert out["dark"]["clip-path"] == "url(#c)"


def test_redact_theme_routes_content_through_content_redactor():
    out = redact_theme({"dark": {"content": '"Buy now"'}})
    assert out["dark"]["content"] == '"<text>"'


def test_redact_theme_none_and_empty_safe():
    assert redact_theme(None) is None
    assert redact_theme({}) == {}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_theme_redacts_box_url_keeps_rgb -v`
Expected: FAIL — `ImportError: cannot import name 'redact_theme'`.

- [ ] **Step 3: Implement**

In `scripts/_style.py`, after `redact_pseudo` (end of file), add:

```python
def redact_theme(themes):
    """Redact one node's theme-delta map {condition: {prop: raw value}}: the
    `content` prop uses redact_content_value; every other prop reuses
    redact_style_value (external/data url() -> url("<asset>"); same-doc
    url(#frag), gradients, raw rgb() colors kept). Mirrors redact_pseudo. content
    never actually appears (theme deltas are element-node-scoped, where content
    resolves to `normal`) but is routed correctly as a safety belt. None/empty-
    safe; idempotent."""
    if not themes:
        return themes
    return {label: {p: (redact_content_value(v) if p == "content"
                        else redact_style_value(v))
                    for p, v in delta.items()}
            for label, delta in themes.items()}
```

- [ ] **Step 4: Run tests**

Run: `cd scripts && python3 -m pytest test_style.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_theme mirroring redact_pseudo"
```

---

## Task 5: `bundle_writer.apply_node_theme` + thread through assemble/main

**Files:**
- Modify: `scripts/bundle_writer.py` (`apply_node_theme` after `apply_node_pseudo` ~161; `assemble` sig ~163 + body ~172; `main` pops ~240)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_bundle_writer.py`:

```python
def test_apply_node_theme_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_theme = {0: {"dark": {"color": "rgb(240, 240, 240)",
                               "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_theme(nodes, node_theme)
    assert nodes[0]["theme"]["dark"]["color"] == "rgb(240, 240, 240)"
    assert nodes[0]["theme"]["dark"]["background-image"] == 'url("<asset>")'
    assert "theme" not in nodes[1]            # no entry -> no field


def test_apply_node_theme_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_theme(nodes, None)
    assert "theme" not in nodes[0]
```

(Import alias: the file already imports `bundle_writer as bw` — match the existing convention; if it imports differently, use that name.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_theme_attaches_redacted_delta -v`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_theme'`.

- [ ] **Step 3: Implement**

In `scripts/bundle_writer.py`, after `apply_node_pseudo` (~line 161), add:

```python
def apply_node_theme(nodes, node_theme):
    """Attach each node's theme-delta map as node["theme"], redacted by _style
    (content -> "<text>"; external/data url() -> url("<asset>"); raw rgb kept).
    node_theme: {node_id: {condition: {prop: raw value}}}. Runs BEFORE
    cf.redact_node, which preserves the `theme` key (not a CONTENT_KEYS entry;
    redact_node filters only top-level keys, so the nested redacted map survives).
    No entry -> no field."""
    if not node_theme:
        return
    for n in nodes:
        tv = node_theme.get(n["id"])
        if tv:
            n["theme"] = _style.redact_theme(tv)
```

Change the `assemble` signature (~line 163) from:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None):
```

to:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None):
```

In `assemble` body, after `apply_node_pseudo(nodes, node_pseudo)` (~line 172), add:

```python
    apply_node_theme(nodes, node_theme)
```

In `main`, after the `raw_pseudo`/`node_pseudo` block (~line 240), add:

```python
    raw_theme = skeleton.pop("_node_theme", {})
    node_theme = {int(k): v for k, v in raw_theme.items()}
    skeleton.pop("_node_backend", None)   # internal join key — never reaches disk
```

In `main`, update the `assemble(...)` call to pass `node_theme=node_theme` (add the kwarg to the existing call alongside `node_style`/`node_pseudo`).

- [ ] **Step 4: Run tests**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: apply_node_theme threads theme deltas into bundle"
```

---

## Task 6: Firewall canary (tests only — `content_firewall.py` UNCHANGED)

**Files:**
- Test: `scripts/test_content_firewall.py`

**Context:** `theme` is NOT a `CONTENT_KEYS` entry, so `redact_node` keeps the nested (already-redacted) map and `audit_bundle._walk_strings` recurses into `node.theme[label][prop]` as the independent backstop. These tests lock that in. Do NOT modify `content_firewall.py`.

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_content_firewall.py` (match the file's existing helper for building a minimal skeleton/bundle on disk + calling `audit_bundle`; mirror the existing `test_audit_passes_skeleton_with_pseudo` / `test_audit_canary_unredacted_url_in_pseudo_trips` pattern exactly):

```python
def test_audit_passes_skeleton_with_theme(tmp_path):
    # a node carrying a properly-redacted theme delta must audit CLEAN
    bundle = _minimal_bundle()  # reuse the file's existing builder
    bundle["skeleton"]["nodes"][0]["theme"] = {
        "dark": {"color": "rgb(240, 240, 240)",
                 "background-image": 'url("<asset>")'}}
    _write_bundle_dir(tmp_path, bundle)   # reuse the file's existing writer
    assert cf.audit_bundle(tmp_path) == []


def test_audit_canary_unredacted_url_in_theme_trips(tmp_path):
    # an UN-redacted external url in a theme delta MUST be caught by the backstop
    bundle = _minimal_bundle()
    bundle["skeleton"]["nodes"][0]["theme"] = {
        "dark": {"background-image": 'url("https://leak.example.com/secret.png")'}}
    _write_bundle_dir(tmp_path, bundle)
    viol = cf.audit_bundle(tmp_path)
    assert viol, "un-redacted external url in theme delta must trip the audit"
```

If the existing tests use different helper names than `_minimal_bundle`/`_write_bundle_dir`, READ the file first and reuse whatever the pseudo canary tests use — do not invent new helpers.

- [ ] **Step 2: Run test to verify it fails (canary) / passes (clean)**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -k theme -v`
Expected: `test_audit_passes_skeleton_with_theme` PASS immediately (firewall already recurses); `test_audit_canary_unredacted_url_in_theme_trips` PASS immediately (backstop already catches external urls anywhere). If the canary does NOT trip, that is a real firewall gap — STOP and report (do not weaken the test).

- [ ] **Step 3: (no implementation — firewall unchanged)**

- [ ] **Step 4: Run full firewall suite**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: lock firewall clean+canary for theme deltas"
```

---

## Task 7: `web_skeleton` `--themes` orchestration (CDP recapture)

**Files:**
- Modify: `scripts/web_skeleton.py` (`_snapshot_skeleton`/`_capture_one` 4th return; `THEME_PROPS`/`BASE_FEATURES`/`CONDITION_OVERRIDE`; `_condition_features`/`_styles_by_backend`/`capture_with_themes`; `main` `--themes`)
- Modify: `scripts/web_states.py` (migrate one `_snapshot_skeleton` unpack)

**Note on testing:** this task is CDP I/O orchestration; its correctness is proven by the host gate (Task 8), not a unit test (no CDP fake exists). The pure logic it calls is already unit-tested (Tasks 2,3). The acceptance bar for THIS task is: full existing suite stays green (no migration breakage). Step 4 runs the whole suite.

- [ ] **Step 1: Thread `node_backend` out of `_snapshot_skeleton` and `_capture_one`**

In `_snapshot_skeleton`, the unpack is already 5-value (Task 2 step 5). Change its return (~line 572) from:

```python
    return sk, layout, page
```

to:

```python
    return sk, layout, page, node_backend
```

In `_capture_one` (~line 575-588), change the unpack and return:

```python
    sk, layout, page, node_backend = _snapshot_skeleton(ev, url, width=width)
    sk["settle"] = settle
    return sk, layout, page, node_backend
```

Migrate `_capture_one` callers in `web_skeleton.main`:
- viewports branch (~line 660): `sk, _, _ = _capture_one(...)` → `sk, _, _, _ = _capture_one(...)`
- single branch (~line 671): `out_obj, _, _ = _capture_one(...)` → `out_obj, _, _, _ = _capture_one(...)`

Migrate the `web_states.py` call to `_snapshot_skeleton` (find it: `grep -n "_snapshot_skeleton" web_states.py`) from `sk, ... = _snapshot_skeleton(...)` to absorb the 4th value, e.g. `sk, _, _, _ = ws._snapshot_skeleton(...)` (or `sk, *rest = ...` if it currently uses partial unpack). Match the existing variable usage — only widen the unpack arity.

- [ ] **Step 2: Add the theme constants and helpers**

In `web_skeleton.py`, after `STYLE_PROPS` (~line 100) add:

```python
# Regime-3a: theme/preference diff. THEME_PROPS = the Regime-1 visual prop set +
# the three colors the _node_colors model holds (a subset of WANT_STYLES, so every
# value is present in a record's raw `style`). Geometry/sizing props are excluded —
# theme conditions restyle via color/effect, not box metrics; a display:none toggle
# is handled by drop-on-miss, not by diffing `display`.
THEME_PROPS = STYLE_PROPS + ["color", "background-color", "border-top-color"]

# Pinned DEFAULT media for the base capture (design §3) — do NOT rely on ambient
# OS/headless defaults, or the delta becomes environment-dependent.
BASE_FEATURES = [
    {"name": "prefers-color-scheme", "value": "light"},
    {"name": "forced-colors", "value": "none"},
    {"name": "prefers-contrast", "value": "no-preference"},
]
# Each condition flips EXACTLY ONE feature off the pinned base (single-axis delta).
CONDITION_OVERRIDE = {
    "dark": {"name": "prefers-color-scheme", "value": "dark"},
    "forced-colors": {"name": "forced-colors", "value": "active"},
    "contrast": {"name": "prefers-contrast", "value": "more"},
}


def _condition_features(label):
    """BASE_FEATURES with the single feature for `label` overridden."""
    ov = CONDITION_OVERRIDE[label]
    return [ov if f["name"] == ov["name"] else f for f in BASE_FEATURES]
```

Add `import _theme` to the imports at the top of `web_skeleton.py` (alongside the other `_`-module imports).

- [ ] **Step 3: Add `_styles_by_backend` and `capture_with_themes`**

In `web_skeleton.py`, after `_snapshot_skeleton` (before `_capture_one`), add:

```python
def _styles_by_backend(ev):
    """Capture ONE DOMSnapshot at the page's CURRENT emulation + REST and return
    {backendNodeId: full resolved style dict} for element nodes. NO navigate — the
    caller flips Emulation.setEmulatedMedia between calls. dpr is irrelevant here
    (style-only; bbox unused)."""
    ev.ev(_REST_JS)
    time.sleep(0.15)
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WANT_STYLES, "includeDOMRects": True,
                         "includePaintOrder": True})
    recs = parse_snapshot(snap, WANT_STYLES, dpr=1.0)
    return _theme.styles_by_backend(recs)


def capture_with_themes(ev, engine, url, labels, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton under pinned default media, then for each theme
    `label` recapture under that single-axis condition and diff full resolved
    styles vs base (THEME_PROPS); attach per-condition deltas as the _node_theme
    sidecar (keyed by node id; backendNodeId stays internal). Base + every
    condition use identical capture params (phantom-diff guard, design §3).
    Clears emulation in finally so the operator's tab is left unpolluted.

    Note: base styles are captured a second time via _styles_by_backend right
    after the base _capture_one (still under pinned base, no navigate). This
    deliberate extra snapshot avoids threading raw styles out of _capture_one;
    backendNodeId is stable so the two base captures join exactly."""
    try:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": BASE_FEATURES})
        sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
        base_styles = _styles_by_backend(ev)
        per_condition = {}
        for label in labels:
            ev.sess.send("Emulation.setEmulatedMedia",
                         {"features": _condition_features(label)})
            time.sleep(0.3)   # let the restyle settle before recapture
            cond_styles = _styles_by_backend(ev)
            delta = _theme.diff_theme(base_styles, cond_styles, THEME_PROPS)
            per_condition[label] = _theme.rekey_by_node_id(delta, node_backend)
        node_theme = _theme.build_node_theme(per_condition)
        sk["_node_theme"] = {str(k): v for k, v in node_theme.items()}
        return sk
    finally:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": []})
```

- [ ] **Step 4: Wire the `--themes` flag in `main`**

In `web_skeleton.main`, add the argument (after `--viewports`):

```python
    p.add_argument("--themes", default=None,
                   help="comma labels from {dark,forced-colors,contrast}; capture "
                        "per-node resolved style deltas under each emulated-media "
                        "condition into the _node_theme sidecar")
```

Add a branch BEFORE the `if args.viewports:` branch (themes and viewports are mutually exclusive for this cut — they both drive Emulation):

```python
    if args.themes:
        labels = [s.strip() for s in args.themes.split(",") if s.strip()]
        bad = [l for l in labels if l not in CONDITION_OVERRIDE]
        if bad:
            die(f"web_skeleton --themes: unknown {bad}; choose from "
                f"{sorted(CONDITION_OVERRIDE)}")
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --themes needs a CDP transport "
                    "(Emulation.setEmulatedMedia). Use chrome host / --cdp-port.")
            out_obj = capture_with_themes(ev, engine, args.url, labels,
                                          max_wait=args.max_wait)
        finally:
            ev.close()
    elif args.viewports:
        ...  # existing viewports branch unchanged
    else:
        ...  # existing single-capture branch unchanged
```

(Convert the existing `if args.viewports:` to `elif args.viewports:` and keep its body and the `else:` body exactly as-is.)

- [ ] **Step 5: Run the full suite (acceptance bar for plumbing)**

Run: `cd scripts && python3 -m pytest -q`
Expected: full suite GREEN (no migration breakage; new theme/style/bundle/firewall tests pass). Note the new total.

- [ ] **Step 6: Commit**

```bash
git add scripts/web_skeleton.py scripts/web_states.py
git commit -m "feat: web_skeleton --themes captures emulated-media style deltas"
```

---

## Task 8: Synthetic host gate — proves JOIN CORRECTNESS (controller runs CDP)

**Files:**
- Create: `fixtures/theme/run_theme.py`

**Context:** CDP is unreachable from the subagent sandbox. The IMPLEMENTER writes the gate file only. The CONTROLLER runs it on the host (`dangerouslyDisableSandbox=true`) and commits. The gate must prove the JOIN, not merely that "deltas appear": the right delta lands on the right node; an unchanged node gets no delta.

- [ ] **Step 1: Write the gate**

Create `fixtures/theme/run_theme.py` (mirror `fixtures/css_style/run_css_style.py`'s local-server + subprocess(web_skeleton → bundle_writer) structure; READ that file first for the exact bootstrap — server thread, `resolve` of script paths, how it invokes the CLIs, how it loads the resulting `skeleton.json`):

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --themes captures per-node resolved style deltas under
prefers-color-scheme:dark / forced-colors:active / prefers-contrast:more, and the
pipeline redacts them content-free. PROVES JOIN CORRECTNESS: a node whose color
changes under dark gets the RIGHT dark delta; a node with NO theme rule gets NO
delta. Deterministic, offline (data: URL via a local server or file). Runs on host
CDP. bundle_writer.write_bundle runs the firewall audit and RAISES on leak."""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from web_tokens import parse_color  # noqa: E402  (format-robust rgb compare)

# #known: distinct base bg rgb(200,200,200); restyles under dark + contrast.
# #static: no @media rule -> MUST get no theme delta.
_PAGE = """<!doctype html><meta charset=utf-8><title>theme-gate</title>
<style>
 #known { width:120px; height:60px; color: rgb(10,20,30);
          background-color: rgb(200,200,200); }
 #static { width:80px; height:40px; color: rgb(50,60,70);
           background-color: rgb(123,124,125); }
 @media (prefers-color-scheme: dark) {
   #known { color: rgb(240,240,240); background-color: rgb(17,17,17); }
 }
 @media (prefers-contrast: more) {
   #known { color: rgb(0,0,0); }
 }
</style>
<div id=known>k</div><div id=static>s</div>"""


def _serve(page_bytes):
    # reuse run_css_style.py's ThreadingHTTPServer pattern; return base_url
    ...  # IMPLEMENTER: copy the server helper from run_css_style.py verbatim


def _node_by_bg(nodes, rgb, palette):
    """Find the emitted node whose base bg resolves to `rgb` (format-robust via
    parse_color against the bundle palette token_ref)."""
    ...  # IMPLEMENTER: mirror run_css_style.py's color-match helper (MARK_RGB)


def _check(bundle_dir):
    sk = json.loads((Path(bundle_dir) / "skeleton.json").read_text())
    nodes = sk.get("nodes") or []
    themed = [n for n in nodes if n.get("theme")]
    assert themed, "GATE FAIL: no node carried a theme delta"

    # JOIN CORRECTNESS 1: the #known node's dark delta is the resolved dark color.
    # (match #known by its base bg rgb(200,200,200))
    known = _node_by_bg(nodes, (200, 200, 200), sk)
    assert known is not None and known.get("theme"), "GATE FAIL: #known has no theme"
    dark = known["theme"].get("dark", {})
    assert parse_color(dark.get("color")) == (240, 240, 240), \
        f"GATE FAIL: wrong dark color delta: {dark.get('color')}"
    assert parse_color(dark.get("background-color")) == (17, 17, 17), \
        f"GATE FAIL: wrong dark bg delta: {dark.get('background-color')}"
    # contrast delta on the same node
    contrast = known["theme"].get("contrast", {})
    assert parse_color(contrast.get("color")) == (0, 0, 0), \
        f"GATE FAIL: wrong contrast delta: {contrast.get('color')}"
    # forced-colors produced SOME delta on #known
    assert known["theme"].get("forced-colors"), "GATE FAIL: no forced-colors delta"

    # JOIN CORRECTNESS 2: #static (no @media rule) gets NO theme delta.
    static = _node_by_bg(nodes, (123, 124, 125), sk)
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("theme"), "GATE FAIL: #static got a spurious theme delta"

    print("GATE PASS: theme join correct (#known dark/contrast/forced-colors deltas "
          "right; #static clean); bundle audit CLEAN")


def main():
    base_url = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "theme" / "_bundle"
    sk_json = ROOT / "fixtures" / "theme" / "_sk.json"
    tok_json = ROOT / "fixtures" / "theme" / "_tokens.json"
    # 1) capture with themes
    subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                    "--url", base_url, "--themes", "dark,forced-colors,contrast",
                    "--out", str(sk_json)], check=True)
    # 2) tokens (web_tokens) — mirror run_css_style.py's invocation
    subprocess.run([sys.executable, str(SCRIPTS / "web_tokens.py"),
                    "--url", base_url, "--out", str(tok_json)], check=True)
    # 3) bundle (runs firewall audit; raises on leak)
    subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                    "--skeleton", str(sk_json), "--tokens", str(tok_json),
                    "--out", str(out)], check=True)
    _check(out)


if __name__ == "__main__":
    main()
```

IMPLEMENTER: fill the three `...` helpers by copying the corresponding helpers from `fixtures/css_style/run_css_style.py` verbatim (server thread + color-match). Do NOT invent new transport. The web_tokens/bundle_writer invocation flags must match how `run_css_style.py` calls them.

- [ ] **Step 2: (implementer) static check only**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 -c "import ast; ast.parse(open('fixtures/theme/run_theme.py').read()); print('parses')"`
Expected: `parses`. (Implementer cannot run CDP — stop here, report DONE.)

- [ ] **Step 3: (CONTROLLER, host) run the gate**

Controller runs on host with `dangerouslyDisableSandbox=true`:
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/theme/run_theme.py`
Expected: `GATE PASS: ...`. If FAIL, controller feeds the exact failure back to a fix subagent.

- [ ] **Step 4: Commit (controller, after GATE PASS)**

```bash
git add fixtures/theme/run_theme.py
git commit -m "test: add Regime-3a theme host gate proving join correctness"
```

---

## After all tasks (controller)

- [ ] **Full suite:** `cd scripts && python3 -m pytest -q` → all green; record the new total.
- [ ] **Real-site validation (content-free, host):** write a one-off `fixtures/theme/validate_realsite.py` (mirror `fixtures/css_style/validate_realsite.py`) that runs `web_skeleton --themes dark,forced-colors,contrast` against a dark-mode-capable public page, builds the bundle (audit must not raise), and prints ONLY content-free signal: per-condition `{label: nodes-with-delta count, total changed-prop count}`. MUST report **forced-colors volume** explicitly (it is dense by design §9 — confirm it does not silently balloon the bundle). NEVER print a resolved value, selector content, or url. Confirm `write_bundle` audit CLEAN at scale.
- [ ] **Docs:** add `§C9-R-P9 — Regime-3a theme/preference LANDED` to `docs/plans/probe-runner-engine-capture-gaps.md` (content-free summary: join key, conditions, forced-colors density measurement, ceilings); correct the Regime-3 theme rows in `docs/research/css-capture-completeness.md` (§9 `prefers-color-scheme`/`prefers-contrast`/`forced-colors` rows → LANDED via 3a style-delta capture).
- [ ] **Final whole-implementation review:** dispatch a final code-reviewer subagent over the full commit range; write the verdict to `docs/plans/regime3a-theme-preference-capture-final-review.md`.
- [ ] **Advisor done-gate** before declaring complete.

---

## Self-Review (writing-plans)

**Spec coverage:** §1 join → T1,T2; §3 base-pin + phantom-guard + finally-clear → T7; §5 diff core → T3; §6 redaction → T4; §7 bundle → T5; §8 firewall → T6; §9 ceilings (drop-on-miss in `diff_theme`, forced-colors volume in real-site) → T3,after-tasks; §10 testing → T3,4,5,6,8; §11 files → all. Covered.

**Type consistency:** `node_backend` = `{node_id: backendNodeId}` (T2,T3,T7); `_node_theme` sidecar = `{str(node_id): {label: {prop: val}}}` on disk, `{int: ...}` in `main` (T5,T7); `diff_theme` returns `{backend: {prop: val}}`, `rekey_by_node_id` → `{node_id: ...}`, `build_node_theme` → `{node_id: {label: ...}}` (T3); `redact_theme` takes/returns `{label: {prop: val}}` (T4); `apply_node_theme` reads `node_theme[n["id"]]` (T5). Consistent across tasks.

**Placeholder scan:** the only `...` are in the Task-8 gate, each annotated "copy verbatim from run_css_style.py" — intentional (the helper is an exact reuse of an existing file the implementer must read), not a spec gap.
