# Reduced-motion Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture, as an additive per-node `reduced_motion` sidecar, the computed-style DELTA each element exhibits under emulated `prefers-reduced-motion: reduce` (which animation/transition/scroll props the design suppresses), content-free, joined by `backendNodeId`.

**Architecture:** A near-clone of Regime-3a's single-condition flow. `web_skeleton.capture_with_reduced_motion` does one navigate, snapshots `MOTION_PROPS` under emulated `prefers-reduced-motion: no-preference` (base) then `reduce` (condition), diffs via the `_theme` pure core, and attaches a `_node_reduced_motion` sidecar. Threaded through `bundle_writer` exactly like `theme`/`responsive`; redacted by `_style.redact_reduced_motion`, a true **ALIAS** of `redact_theme` (same flat `{label:{prop:value}}` shape); `content_firewall.py` UNCHANGED.

**Tech Stack:** Python 3, CDP (`Emulation.setEmulatedMedia` / `DOMSnapshot.captureSnapshot`), pytest. Host CDP gate runs on host Bash (CDP unreachable from the ctx sandbox).

**Design spec:** `docs/plans/reduced-motion-capture-design.md` (probe facts PR1–PR4 in §1; the controller has run and deleted that probe — measured: emulation effective; 6 props move; `animation-play-state` excluded; delta is theme-shape).

---

## File structure (what this plan creates / modifies)

- **Modify** `scripts/_style.py` — append `redact_reduced_motion = redact_theme` alias (T1).
- **Modify** `scripts/test_style.py` — alias + shape test (T1).
- **Modify** `scripts/bundle_writer.py` — `apply_node_reduced_motion`; `assemble(..., node_reduced_motion=None)`; `main` pops `_node_reduced_motion` (T2).
- **Modify** `scripts/test_bundle_writer.py` — `apply_node_reduced_motion` round-trip + None-safe (T2).
- **Modify** `scripts/test_content_firewall.py` — prose canary into `reduced_motion` (T3). `content_firewall.py` UNCHANGED.
- **Modify** `scripts/web_skeleton.py` — `MOTION_PROPS` constant; `capture_with_reduced_motion`; `--reduced-motion` flag + branch (T4).
- **Modify** `scripts/test_web_skeleton.py` — constants shape test; `capture_with_reduced_motion` orchestration tests (T4).
- **Create** `fixtures/reduced-motion/run_reduced_motion.py` — host CDP gate (T5, controller-run).
- **Create** `fixtures/reduced-motion/validate_realsite.py` — content-free real-site harness (after-task, controller-run).

**Commit discipline (standing constraints — non-negotiable):** single-line commit messages, NO trailers / NO `Co-Authored-By` / NO body. Stage files EXPLICITLY by path; NEVER `git add -A`/`git add .`. ONE commit per task; a review-driven fix gets its OWN commit. Do NOT push. `backendNodeId` / CDP `nodeId` NEVER on disk. Implementer subagents write gate/harness files + static-check only (`python3 -c "import ast; ast.parse(open(...).read())"`); the CONTROLLER runs the CDP gate (T5) and all after-tasks.

---

### Task 1: `redact_reduced_motion` alias

**Files:**
- Modify: `scripts/_style.py` (after the `redact_keyframes` function, near the `redact_responsive`/`redact_pseudo_state` aliases)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_style.py`, extend the import block and add a test:

```python
from _style import redact_reduced_motion  # noqa: E402
```

```python
def test_redact_reduced_motion_is_redact_theme_alias():
    # reduced_motion is a flat {label:{prop:value}} delta, identical in shape to a theme
    # delta -> the redactor is the SAME function (alias), like redact_pseudo_state/responsive.
    assert redact_reduced_motion is redact_theme
    out = redact_reduced_motion({"reduce": {"animation-name": "none",
                                            "transition-duration": "0s",
                                            "scroll-behavior": "auto"}})
    assert out == {"reduce": {"animation-name": "none", "transition-duration": "0s",
                              "scroll-behavior": "auto"}}
    assert redact_reduced_motion(None) is None
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py::test_redact_reduced_motion_is_redact_theme_alias -q`
Expected: FAIL — `ImportError: cannot import name 'redact_reduced_motion'`.

- [ ] **Step 3: Add the alias**

In `scripts/_style.py`, grep for `redact_responsive = redact_theme` and the `redact_keyframes` function. After the `redact_keyframes` function (the last redactor), add the alias next to the other condition aliases:

```python
# Regime-P13 reduced-motion: the per-node delta is the flat {label:{prop:value}} theme
# shape (single label "reduce"), so its redactor is the SAME walker — an alias, exactly
# like redact_pseudo_state / redact_responsive. (Contrast redact_keyframes, which needed
# its own walker for the [{timing,frames}] shape.)
redact_reduced_motion = redact_theme
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py -q`
Expected: PASS (all, including the new one).

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_reduced_motion alias for the reduced-motion delta"
```

---

### Task 2: `apply_node_reduced_motion` + bundle threading

**Files:**
- Modify: `scripts/bundle_writer.py` (locate by pattern: `apply_node_keyframes`, `def assemble`, the `_node_keyframes` pop in `main`)
- Test: `scripts/test_bundle_writer.py` (module imported as `bw`)

IMPORTANT: cited positions are approximate — LOCATE EACH ANCHOR BY PATTERN (grep). Mirror the most recent sibling `apply_node_keyframes` and the `theme` threading.

- [ ] **Step 1: Write the failing tests**

In `scripts/test_bundle_writer.py`, add after the `test_apply_node_keyframes_*` tests:

```python
def test_apply_node_reduced_motion_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_rm = {0: {"reduce": {"animation-name": "none", "animation-duration": "0s",
                              "scroll-behavior": "auto"}}}
    bw.apply_node_reduced_motion(nodes, node_rm)
    assert nodes[0]["reduced_motion"]["reduce"]["animation-name"] == "none"
    assert nodes[0]["reduced_motion"]["reduce"]["scroll-behavior"] == "auto"
    assert "reduced_motion" not in nodes[1]        # no entry -> no field


def test_apply_node_reduced_motion_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_reduced_motion(nodes, None)
    bw.apply_node_reduced_motion(nodes, {})
    assert "reduced_motion" not in nodes[0]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_reduced_motion_attaches_redacted_delta -q`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_reduced_motion'`.

- [ ] **Step 3: Add `apply_node_reduced_motion`**

In `scripts/bundle_writer.py`, immediately after `apply_node_keyframes` and before `def assemble`, add:

```python
def apply_node_reduced_motion(nodes, node_rm):
    """Attach each node's reduced-motion computed-style delta as node["reduced_motion"],
    redacted by _style (flat {label:{prop:value}} shape; redact_reduced_motion is a
    redact_theme alias). node_rm: {node_id: {"reduce": {prop: value}}}. Runs BEFORE
    cf.redact_node, which preserves the `reduced_motion` key (not a CONTENT_KEYS entry).
    No entry / empty delta -> no field. This is the declared prefers-reduced-motion:reduce
    adaptation, sibling to the theme/pseudo_state/responsive deltas (same shape)."""
    if not node_rm:
        return
    for n in nodes:
        rv = node_rm.get(n["id"])
        if rv:
            n["reduced_motion"] = _style.redact_reduced_motion(rv)
```

- [ ] **Step 4: Thread through `assemble`**

Grep for `def assemble`. Add a trailing `node_reduced_motion=None` kwarg to the signature (after the existing `node_keyframes=None`):

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None,
             node_responsive=None, node_keyframes=None, node_reduced_motion=None):
```

Inside `assemble`, immediately after the existing `apply_node_keyframes(nodes, node_keyframes)` line, add (match indentation):

```python
    apply_node_reduced_motion(nodes, node_reduced_motion)
```

(Order: ...→ node_keyframes → node_reduced_motion → `motion = match_motion(...)` → `cf.redact_node`.)

- [ ] **Step 5: Thread through `main`**

In `main`, grep for `raw_keyframes = skeleton.pop("_node_keyframes"`. Immediately after that pair and BEFORE `skeleton.pop("_node_backend", None)`, add:

```python
    raw_reduced_motion = skeleton.pop("_node_reduced_motion", {})
    node_reduced_motion = {int(k): v for k, v in raw_reduced_motion.items()}
```

Then extend the `assemble(...)` call — find the kwarg `node_keyframes=node_keyframes` and append `, node_reduced_motion=node_reduced_motion`:

```python
                      node_keyframes=node_keyframes, node_reduced_motion=node_reduced_motion)
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: PASS (all, including the two new). The default-None addition must not break any existing assemble/round-trip test.

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: thread reduced-motion delta through bundle assemble"
```

---

### Task 3: Firewall prose canary into `reduced_motion`

**Files:**
- Modify: `scripts/test_content_firewall.py`
- `scripts/content_firewall.py` — **UNCHANGED** (flat dict nesting like `theme`; `audit_bundle`'s key-aware walk already recurses it).

- [ ] **Step 1: Write the test**

In `scripts/test_content_firewall.py` (module `cf`, helper `_clean_bundle`), add (mirror the `theme`/`keyframes` canaries):

```python
def test_audit_canary_unredacted_prose_in_reduced_motion_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["reduced_motion"]["reduce"][prop]: an un-redacted PROSE leak there trips ONLY
    # via the key-aware prose walk (the flat URL/base64 detectors do NOT match plain prose).
    # If redact_reduced_motion ever failed to redact a value, THIS is the backstop. Mirrors
    # the theme/pseudo_state/responsive/keyframes prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "reduced_motion": {"reduce": {"animation-name":
                                                   "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a reduced_motion delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves reduced_motion recursion), not a flat detector"
```

- [ ] **Step 2: Run to verify it passes immediately**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_content_firewall.py::test_audit_canary_unredacted_prose_in_reduced_motion_trips -q`
Expected: **PASS without touching `content_firewall.py`** (TDD inversion — the existing walker already reaches the new key, the same flat dict nesting as `theme`). If it FAILS, STOP and escalate; do NOT modify the firewall.

- [ ] **Step 3: Run the full firewall suite**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: add firewall prose canary for reduced-motion delta"
```

---

### Task 4: `capture_with_reduced_motion` + `--reduced-motion` flag

**Files:**
- Modify: `scripts/web_skeleton.py` (locate by pattern: the responsive/keyframes constants block, `def capture_with_keyframes`, `def _capture_one`, the `--keyframes` argparse + `elif args.keyframes:` branch, `capture_with_themes` to MIRROR)
- Test: `scripts/test_web_skeleton.py` (module `ws`)

**Model:** integration/judgment task (multi-step CDP orchestration) — dispatch with a capable model (opus).

**Mirror `capture_with_themes` verbatim for the backend→node_id sequence:** it does `delta = _theme.diff_theme(base, cond, PROPS)`, then `per_condition[label] = _theme.rekey_by_node_id(delta, node_backend)` (rekey PER label), then `node_x = _theme.build_node_theme(per_condition)` (transpose), then `sk["_node_x"] = {str(k): v ...}`. Use that exact sequence with a single label `"reduce"`. Do NOT use the `_styles_by_backend(ev)` wrapper (it snapshots the default `WANT_STYLES`); `MOTION_PROPS` is NOT a subset of `WANT_STYLES`, so snapshot it EXPLICITLY via `_theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))` (the `capture_with_breakpoints` pattern).

- [ ] **Step 1: Write the failing tests**

In `scripts/test_web_skeleton.py`, add:

```python
def test_motion_props_curated():
    for p in ("animation-name", "animation-duration", "animation-iteration-count",
              "transition-duration", "transition-property", "scroll-behavior"):
        assert p in ws.MOTION_PROPS
    # animation-play-state excluded (probe PR3: does not move when animation is turned off)
    assert "animation-play-state" not in ws.MOTION_PROPS
    # layout-thrash props excluded
    for p in ("width", "height", "top"):
        assert p not in ws.MOTION_PROPS


def test_capture_with_reduced_motion_diffs_base_vs_reduce(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    # distinct backend != node_id so a rekey misplacement surfaces here (not only the gate)
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))

    # _snapshot_recs is called twice: 1st = base (no-preference), 2nd = reduce.
    calls = {"n": 0}
    base_recs = [
        {"backend": 5, "pseudo": None, "style": {"animation-name": "drift",
            "animation-duration": "2s", "animation-iteration-count": "infinite",
            "transition-duration": "0.5s", "transition-property": "opacity",
            "scroll-behavior": "smooth"}},
        {"backend": 7, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "all",
            "scroll-behavior": "auto"}}]
    reduce_recs = [
        {"backend": 5, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "none",
            "scroll-behavior": "auto"}},
        {"backend": 7, "pseudo": None, "style": {"animation-name": "none",
            "animation-duration": "0s", "animation-iteration-count": "1",
            "transition-duration": "0s", "transition-property": "all",
            "scroll-behavior": "auto"}}]

    def fake_snapshot(ev, props=None):
        calls["n"] += 1
        return base_recs if calls["n"] == 1 else reduce_recs
    monkeypatch.setattr(W, "_snapshot_recs", fake_snapshot)

    sk = W.capture_with_reduced_motion(ev, "chrome", "http://x")

    # node 0 (backend 5) moved on all 6 props; node 1 (backend 7) unchanged -> no entry.
    assert sk["_node_reduced_motion"] == {"0": {"reduce": {
        "animation-name": "none", "animation-duration": "0s",
        "animation-iteration-count": "1", "transition-duration": "0s",
        "transition-property": "none", "scroll-behavior": "auto"}}}
    assert "1" not in sk["_node_reduced_motion"]
    # emulated-media sequence: base no-preference, then reduce, then cleared.
    media = [p["features"] for (m, p) in sent if m == "Emulation.setEmulatedMedia"]
    assert media[0] == [{"name": "prefers-reduced-motion", "value": "no-preference"}]
    assert media[1] == [{"name": "prefers-reduced-motion", "value": "reduce"}]
    assert media[-1] == []          # cleared in finally


def test_capture_with_reduced_motion_clears_emulation_on_error(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def close(self): pass

    ev = FakeEv()

    def boom(ev, engine, url, width=None, max_wait=None):
        raise RuntimeError("capture failed")
    monkeypatch.setattr(W, "_capture_one", boom)

    import pytest
    with pytest.raises(RuntimeError):
        W.capture_with_reduced_motion(ev, "chrome", "http://x")
    # emulation still cleared in finally even when capture raises
    media = [p["features"] for (m, p) in sent if m == "Emulation.setEmulatedMedia"]
    assert media[-1] == []
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_reduced_motion_diffs_base_vs_reduce -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'capture_with_reduced_motion'` (and `MOTION_PROPS` missing).

- [ ] **Step 3: Add the constant**

In `scripts/web_skeleton.py`, after the `ANIMATABLE_PROPS` constant block (grep for `ANIMATABLE_PROPS`), add:

```python
# Reduced-motion (P13): computed-prop delta under emulated prefers-reduced-motion:reduce.
# MOTION_PROPS = the props measured (probe PR2) to MOVE under reduce — animation off,
# transition off, smooth-scroll off. animation-play-state EXCLUDED (PR3: it does not move
# when animation is turned off, so it carries no signal). NOT a subset of WANT_STYLES, so
# it is snapshotted explicitly (the capture_with_breakpoints pattern).
MOTION_PROPS = ["animation-name", "animation-duration", "animation-iteration-count",
                "transition-duration", "transition-property", "scroll-behavior"]
```

Confirm `_theme` and `time` are imported at the top of `web_skeleton.py` (both are — `capture_with_themes` uses them). Do not add duplicate imports.

- [ ] **Step 4: Add `capture_with_reduced_motion`**

In `scripts/web_skeleton.py`, after `capture_with_keyframes` and before `def _capture_one`, add:

```python
def capture_with_reduced_motion(ev, engine, url, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton under emulated prefers-reduced-motion:no-preference, then
    recapture MOTION_PROPS under :reduce and diff vs base; attach the per-node delta as the
    _node_reduced_motion sidecar (keyed by node id; backendNodeId stays internal). One
    navigate, single condition. Mirrors capture_with_themes (the _theme pure core does the
    backendNodeId->node_id rekey via rekey_by_node_id, then build_node_theme transposes to
    {node_id: {"reduce": delta}}). MOTION_PROPS is snapshotted explicitly because it is NOT
    a subset of WANT_STYLES.

    CDP-only (the caller guards on hasattr(ev, "sess")). Ceiling (design §6): captures the
    DECLARED reduced-motion adaptation (computed-prop delta) only — JS honoring
    matchMedia('(prefers-reduced-motion: reduce)') is out of scope (web_anim domain). Clears
    emulation in finally so the operator's tab is left unpolluted."""
    try:
        ev.sess.send("Emulation.setEmulatedMedia",
                     {"features": [{"name": "prefers-reduced-motion", "value": "no-preference"}]})
        sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
        base = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))
        ev.sess.send("Emulation.setEmulatedMedia",
                     {"features": [{"name": "prefers-reduced-motion", "value": "reduce"}]})
        time.sleep(0.3)   # let the restyle settle before recapture (mirror capture_with_themes)
        cond = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))
        delta = _theme.diff_theme(base, cond, MOTION_PROPS)
        per_condition = {"reduce": _theme.rekey_by_node_id(delta, node_backend)}
        node_rm = _theme.build_node_theme(per_condition)
        sk["_node_reduced_motion"] = {str(k): v for k, v in node_rm.items()}
        return sk
    finally:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": []})
```

- [ ] **Step 5: Run the orchestration tests**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_reduced_motion_diffs_base_vs_reduce test_web_skeleton.py::test_capture_with_reduced_motion_clears_emulation_on_error test_web_skeleton.py::test_motion_props_curated -q`
Expected: PASS all three.

- [ ] **Step 6: Add the `--reduced-motion` flag + branch**

In `main`, register the flag immediately after the `--keyframes` argument (grep for `--keyframes`):

```python
    p.add_argument("--reduced-motion", action="store_true", default=False,
                   help="capture the per-node computed-style delta under emulated "
                        "prefers-reduced-motion:reduce (Emulation.setEmulatedMedia, "
                        "backendNodeId join) into the _node_reduced_motion sidecar. "
                        "Content-free: changed motion-prop values (animation/transition off, "
                        "scroll-behavior). Declared-variant only (JS honoring is out of scope).")
```

Add the handler branch AFTER the `elif args.keyframes:` block and BEFORE `elif args.viewports:` (grep for `elif args.keyframes:` and `elif args.viewports:`). Note argparse maps `--reduced-motion` to `args.reduced_motion`:

```python
    elif args.reduced_motion:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --reduced-motion needs a CDP transport "
                    "(Emulation.setEmulatedMedia). Use chrome host / --cdp-port.")
            out_obj = capture_with_reduced_motion(ev, engine, args.url, max_wait=args.max_wait)
        finally:
            ev.close()
```

Confirm the branch assigns to `out_obj` (the variable the post-chain write step consumes — same as the sibling branches). MIRROR the `elif args.keyframes:` branch's exact shape; if it differs from this snippet (variable names, guard form), mirror the SIBLING and report the adaptation.

- [ ] **Step 7: Static-check + full suite**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Then `python3 -m pytest test_web_skeleton.py -q` → PASS (full file; the live CLI branch is exercised end-to-end by the host gate in Task 5, which only the controller runs).

- [ ] **Step 8: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add capture_with_reduced_motion and --reduced-motion flag"
```

---

### Task 5: Host CDP gate (controller-run)

**Files:**
- Create: `fixtures/reduced-motion/run_reduced_motion.py`

**Implementer:** write the file and static-check it (`python3 -c "import ast; ast.parse(...)"`). Do NOT run it (CDP unreachable from the ctx sandbox). The CONTROLLER runs it on host Bash with `dangerouslyDisableSandbox=true`.

**Two design facts baked into the page (do NOT alter):** (1) `#known`'s animation is a `translateX` (NOT rotate/scale) — an axis-aligned move keeps the rendered w/h at the authored 40×40 so the node stays bbox-identifiable even mid-animation (the R4a lesson). (2) `scroll-behavior` is declared directly ON `#known` (NOT an ancestor) — `scroll-behavior` is NOT inherited, so the delta lands only on the node that declares it; putting it on `#known` makes `#known` carry the smooth→auto delta.

- [ ] **Step 1: Write the gate**

Create `fixtures/reduced-motion/run_reduced_motion.py`:

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --reduced-motion captures the per-node computed-style delta under
emulated prefers-reduced-motion:reduce, and the pipeline redacts it content-free. PROVES: a
node that declares an animation + transition + scroll-behavior (#known) carries the reduce
delta (animation-name->none, animation-duration->0s, transition-duration->0s,
scroll-behavior->auto); a node with no motion declarations (#static) gets NO reduced_motion
field (isolation); and the internal join keys never reach disk. Deterministic, offline (local
server). bundle_writer.write_bundle runs the firewall audit and RAISES on leak.

Two fixture facts: #known animates via translateX (NOT rotate/scale) so its rendered w/h stays
40x40 and it is identifiable by bbox even mid-animation; scroll-behavior is declared ON #known
(not an ancestor) because scroll-behavior is not inherited — the delta lands on the declaring
node."""
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

_PAGE = """<!doctype html><meta charset=utf-8><title>rm-gate</title>
<style>
 /* translateX (NOT rotate/scale): axis-aligned move keeps rendered w/h at 40x40 so #known
    is bbox-identifiable mid-animation. scroll-behavior declared ON #known (not inherited). */
 @keyframes drift { from { transform: translateX(0);} to { transform: translateX(60px);} }
 #known  { animation: drift 2s linear infinite; transition: opacity .5s ease;
           scroll-behavior: smooth; width:40px; height:40px; }
 #static { width:80px; height:40px; }
 @media (prefers-reduced-motion: reduce) {
   #known { animation: none; transition: none; scroll-behavior: auto; }
 }
</style>
<div id=known></div><div id=static></div>"""

_SIZE = {"known": (40.0, 40.0), "static": (80.0, 40.0)}
_SIZE_TOL = 2.0


def _serve(page_bytes):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page_bytes)))
            self.end_headers()
            self.wfile.write(page_bytes)

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{srv.server_address[1]}/", srv


def _node_by_size(nodes, wh):
    tw, th = wh
    for n in nodes:
        b = n.get("bbox") or {}
        if abs(b.get("w", -1) - tw) <= _SIZE_TOL and abs(b.get("h", -1) - th) <= _SIZE_TOL:
            return n
    return None


def _check(bundle_dir):
    raw = (Path(bundle_dir) / "skeleton.json").read_text()
    sk = json.loads(raw)
    nodes = sk.get("nodes") or []

    assert "_node_reduced_motion" not in sk, "GATE FAIL: internal carrier _node_reduced_motion leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("reduced_motion"), "GATE FAIL: #known has no reduced_motion delta"
    rd = known["reduced_motion"]["reduce"]
    assert rd.get("animation-name") == "none", f"GATE FAIL: #known animation-name not suppressed: {rd}"
    assert rd.get("animation-duration") == "0s", f"GATE FAIL: #known animation-duration not 0s: {rd}"
    assert rd.get("scroll-behavior") == "auto", f"GATE FAIL: #known scroll-behavior not auto: {rd}"
    assert rd.get("transition-duration") == "0s", f"GATE FAIL: #known transition-duration not 0s: {rd}"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("reduced_motion"), \
        f"GATE FAIL: #static got a spurious reduced_motion field (isolation): {static.get('reduced_motion')}"

    print("GATE PASS: reduced-motion delta correct (#known: animation-name->none, "
          "animation-duration->0s, transition-duration->0s, scroll-behavior->auto; #static "
          "isolated — no field); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "reduced-motion" / "_bundle"
    sk_json = ROOT / "fixtures" / "reduced-motion" / "_sk.json"
    tok_json = ROOT / "fixtures" / "reduced-motion" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--reduced-motion", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print(f"web_skeleton FAILED (rc={r.returncode}) — re-run manually to inspect output")
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print(f"bundle_writer FAILED (rc={r.returncode}) — content leak caught by firewall audit")
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Static-check (implementer)**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 -c "import ast; ast.parse(open('fixtures/reduced-motion/run_reduced_motion.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Implementer does NOT execute the gate.

- [ ] **Step 3: Commit (implementer)**

```bash
git add fixtures/reduced-motion/run_reduced_motion.py
git commit -m "test: add reduced-motion host gate fixture"
```

- [ ] **Step 4: CONTROLLER runs the gate on host**

Controller only (host Bash, `dangerouslyDisableSandbox=true`):
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/reduced-motion/run_reduced_motion.py`
Expected: `GATE PASS: ...`. If `#known` carries no delta, the emulated-media restyle or the backend→node_id rekey is broken — STOP and escalate. If `#static` got a field, the diff universe or isolation is wrong. Fix in its OWN commit, re-run.

---

## After-tasks (CONTROLLER only — run after Task 5 gate PASS)

These are NOT plan tasks; the controller executes them directly (host Bash for CDP).

1. **Regression gates** (reduced-motion adds a `_snapshot_recs(ev, MOTION_PROPS)` call + a new `apply_node_*`/`assemble` kwarg but modifies no shared path; still re-run every gate to prove no regression): `python3 fixtures/theme/run_theme.py`, `python3 fixtures/pseudo-state/run_pseudo_state.py`, `python3 fixtures/responsive/run_responsive.py`, `python3 fixtures/keyframes/run_keyframes.py` → each `GATE PASS`.
2. **Full unit suite:** `cd scripts && python3 -m pytest -q` → all green (≥393 baseline + new T1/T2/T3/T4 tests).
3. **gitignore:** add `fixtures/reduced-motion/_sk.json`, `_tokens.json`, `_bundle/` to `.gitignore` (mirror the keyframes block); commit (`chore: gitignore reduced-motion fixture runtime artifacts`). Confirm the gate's runtime artifacts are not tracked.
4. **Real-site validation harness** — create `fixtures/reduced-motion/validate_realsite.py` mirroring the (content-free) `fixtures/keyframes/validate_realsite.py`: prints ONLY host netloc + count of nodes-with-reduced_motion + the SET of changed-prop NAMES + counts; NO values / full URL; failure paths print returncode only (never subprocess stderr). Commit (`test: add reduced-motion content-free real-site validation harness`). Controller runs it against ≥1 public site; audit must be CLEAN; report content-free signal only.
5. **Docs** — add `§C9-R-P13 — Reduced-motion capture LANDED` to `docs/plans/probe-runner-engine-capture-gaps.md` and update its roadmap-status footer (P13 landed; remove "reduced-motion" from Remaining). Commit (`docs: record reduced-motion capture (P13) landed`).
6. **Final code review** — dispatch a final reviewer subagent over the whole commit range; fix any Critical/Important in its OWN commit.
7. **Advisor done-gate**, then report DONE and await the go signal for the next rung. Do NOT push. Do NOT auto-start the next rung.

---

## Self-Review

**1. Spec coverage:** §1 PR1–PR4 → premise behind T4 (gate T5 re-proves the emulated restyle + rekey on #known). §2.1 MOTION_PROPS (6, play-state excluded) → T4 constant + shape test. §2.2 sidecar `{"reduce":{prop:value}}` → T2 (bundle) + T4 (capture). §3 capture flow (base no-preference → reduce → clear; explicit MOTION_PROPS snapshot; rekey via rekey_by_node_id then build_node_theme) → T4. §4 backendNodeId join, never on disk → T4 (distinct backend≠node_id mock) + T5 on-disk locks. §5 reuse + NEW redact alias/apply/capture → T1/T2/T4. §6 ceilings (declared-variant only; no keyframes re-capture; JS out of scope) → T4 docstring. §7 bundle + firewall UNCHANGED → T2 + T3. §8 testing → T1–T5 + after-tasks. §9 CLI `--reduced-motion` → T4.

**2. Placeholder scan:** none — every code step carries complete code; the only described-not-coded item is the real-site harness (after-task), which references `fixtures/keyframes/validate_realsite.py` as the exact pattern to mirror.

**3. Type/name consistency:** `MOTION_PROPS` (list); `capture_with_reduced_motion(ev, engine, url, max_wait=...)`; `_node_reduced_motion` (sidecar key); `reduced_motion` (per-node field); label `"reduce"`; `redact_reduced_motion` (alias, asserted `is redact_theme`); `apply_node_reduced_motion(nodes, node_rm)`; `assemble(..., node_reduced_motion=None)`; `--reduced-motion` flag → `args.reduced_motion`. Names identical across every task. Sidecar values keyed by `str(node_id)`; `main` re-keys via `int(k)` (matches the theme/keyframes pop pattern). The per-node shape `{"reduce": {prop: value}}` is identical in T2 apply tests, T4 orchestration assert, and T5 gate asserts.
```
