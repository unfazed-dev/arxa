# Driven-state transition capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture each driven interaction State's reveal animation as a content-free motion-law (which properties animate + duration + delay + easing) and attach it to that State's `component`.

**Architecture:** Per driven state, the instant after the click (live window, before the existing settle), read the engine's DECLARED law via in-page `document.getAnimations()` over the existing `ev()` transport. A new pure core (`_transition.py`) maps the declared easing onto the existing `_anim_core.EASINGS` cubic-bezier vocabulary and binds each animation to a component-local node by bbox. `web_states.py` wires it in and fixes the click→capture→settle ordering. The declared law is exact-by-construction; coverage is best-effort (snapshot poll-race + JS-rAF blind spot are honest ceilings).

**Tech Stack:** Python 3.13, stdlib only (no numpy). CDP transport (host Chrome). pytest. WAAPI `getAnimations()` in-page JS.

**Design spec:** `docs/plans/driven-state-transition-capture-design.md` (approved 2026-05-31).

**Standing constraints:** Commits single-line, no trailers/body. Stage files explicitly by path (never `git add -A`/`.`). One commit per task. Local on master — do NOT push. Host gates run on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox). Content-free invariant — never persist page text/bytes/real URLs.

---

## File Structure

- **`scripts/_transition.py`** (new) — pure core, no browser, no I/O. `map_easing`, `_bind_node`, `build_transition`, plus the `_parse_one`/`_close` helpers. Imports `EASINGS` from `_anim_core`. Single responsibility: turn raw WAAPI animation records + a component into a content-free `transition`.
- **`scripts/web_states.py`** (modify) — add `_TRANSITION_JS` + `_LIVE_WINDOW`; reorder the per-trigger loop; attach `transition`; add `transitions_built` to the summary; import `build_transition`.
- **`scripts/test_transition.py`** (new) — exhaustive pure-core unit tests.
- **`scripts/test_content_firewall.py`** (modify) — one test: a `transition`-carrying states.json audits content-free.
- **`fixtures/transition/spike_getanimations.py`** (new, Task 0) — host feasibility spike: pins `_LIVE_WINDOW` and confirms which field carries the easing.
- **`fixtures/transition/run_transition.py`** (new, Task 6) — host gate: a page revealing a panel via a 240ms ease-out CSS animation; drives web_states; asserts the captured law.
- **`.gitignore`** (modify) — ignore `fixtures/transition/_out.json`.

---

## Task 0: Feasibility spike (host go/no-go) — BEFORE building

**Why first (advisor #1):** CSS transitions/animations are created on the next style recalc, so `getAnimations()` called in the same microtask as `click()` can return empty. This spike proves a reveal animation is observable, pins the post-click `_LIVE_WINDOW` delay, and reveals whether the easing lands on `getTiming().easing` or per-keyframe `easing`. If nothing is observable over the `ev()`-only transport, STOP and re-evaluate the mechanism before writing any core.

**Files:**
- Create: `fixtures/transition/spike_getanimations.py`

- [ ] **Step 1: Write the spike**

```python
#!/usr/bin/env python3
"""Feasibility spike: is a reveal animation observable in getAnimations() over the
ev() transport, and at what post-click delay? Serves a page whose button reveals a
display:none panel via a CSS @keyframes animation (animation runs from display:none
-> block, unlike an opacity transition which won't). Navigates, clicks, then probes
getAnimations() at several delays, printing per-delay: count, durations, the overall
getTiming().easing, and per-keyframe easings. Go/no-go before building the core.

Run on host Bash (CDP needs host Chrome): python fixtures/transition/spike_getanimations.py
"""
from __future__ import annotations
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from _web_eval import resolve_web_eval, navigate, add_transport_args  # noqa: E402

_PAGE = """<!doctype html><meta charset=utf-8><title>transition-spike</title>
<style>
  body { margin: 0; font-family: sans-serif; }
  #panel { display: none; margin: 40px; width: 320px;
           background: rgb(18,52,86); color: rgb(240,240,240); padding: 16px; }
  #panel.open { display: block; animation: reveal 240ms ease-out both; }
  @keyframes reveal { from { opacity: 0; transform: translateY(8px); }
                      to   { opacity: 1; transform: translateY(0); } }
</style>
<body>
  <button id=btn aria-expanded="false" aria-controls="panel">Open</button>
  <div id=panel role="region"><p id=lbl>Revealed label</p></div>
  <script>
    const b = document.getElementById('btn'), p = document.getElementById('panel');
    b.addEventListener('click', () => {
      // force reflow so the animation restarts each open
      p.classList.remove('open'); void p.offsetWidth;
      const open = p.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  </script>
</body>"""

_CLICK = "(() => { const el = document.querySelector('#btn'); if(!el) return false; el.click(); return true; })()"
_RESET = "(() => { const p = document.querySelector('#panel'); p.classList.remove('open'); return true; })()"
_PROBE = r"""
(() => document.getAnimations().map(a => {
  const e = a.effect, t = e && e.getTiming ? e.getTiming() : {};
  const kfs = (e && e.getKeyframes) ? e.getKeyframes() : [];
  return {duration: t.duration, delay: t.delay, easing: t.easing,
          iterations: Number.isFinite(t.iterations) ? t.iterations : null,
          kfEasings: kfs.map(k => k.easing).filter(Boolean),
          props: [...new Set(kfs.flatMap(k => Object.keys(k).filter(
                   p => !['offset','easing','composite','computedOffset'].includes(p))))],
          playState: a.playState};
}))()
"""


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


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{port}/"

    p = argparse.ArgumentParser()
    add_transport_args(p)
    args = p.parse_args(["--url", url])
    engine, ev, device = resolve_web_eval(args)
    try:
        observed = False
        for delay in (0.016, 0.05, 0.1, 0.2):
            navigate(ev, engine, url)
            ev.ev(_RESET)
            ev.ev(_CLICK)
            time.sleep(delay)
            rows = ev.ev(_PROBE) or []
            print(f"\n=== delay {int(delay*1000)}ms: {len(rows)} animation(s) ===")
            print(json.dumps(rows, indent=2))
            if rows:
                observed = True
    finally:
        ev.close()
        srv.shutdown()
    if observed:
        print("\nSPIKE PASS: reveal animation observable; pick _LIVE_WINDOW = smallest "
              "delay with a non-empty, running row carrying the easing.")
        return 0
    print("\nSPIKE FAIL: no animation observed at any delay — re-evaluate mechanism.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Controller runs the spike on host (NOT a unit test)**

Run on host Bash with `dangerouslyDisableSandbox=true`:
`python fixtures/transition/spike_getanimations.py`
Expected: `SPIKE PASS`, with at least the 50ms and 100ms delays showing 1 running animation, `duration: 240`, `iterations: 1`, and `ease-out` appearing in EITHER `easing` OR `kfEasings`.

Record two findings for Task 3 and Task 1:
1. **`_LIVE_WINDOW`** = the smallest delay (in seconds) that reliably shows a running row (expected `0.05`).
2. **Which field carries the easing** (`getTiming().easing` vs per-keyframe `kfEasings`). `map_easing` already reads both, so this is confirmation, not a code change.

If `SPIKE FAIL`: stop, report to the controller/human — the mechanism (not the plan) needs revisiting.

- [ ] **Step 3: Commit the spike**

```bash
git add fixtures/transition/spike_getanimations.py
git commit -m "test: add getAnimations feasibility spike for driven-state transitions"
```

---

## Task 1: `_transition.py` — `map_easing` (pure)

**Files:**
- Create: `scripts/_transition.py`
- Test: `scripts/test_transition.py`

- [ ] **Step 1: Write the failing tests**

Create `scripts/test_transition.py`:

```python
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _transition import map_easing, _bind_node, build_transition  # noqa: E402


def test_map_easing_named_keyword_certifies():
    r = map_easing("ease-out", [])
    assert r == {"klass": "ease-out", "bezier": [0, 0, 0.58, 1],
                 "certified": True, "reason": None}


def test_map_easing_cubic_bezier_matches_named_within_tol():
    # cubic-bezier(.25,.1,.25,1) == the "ease" standard curve
    r = map_easing("cubic-bezier(0.25, 0.1, 0.25, 1)", [])
    assert r["klass"] == "ease" and r["certified"] is True


def test_map_easing_custom_cubic_bezier_kept_raw_and_certified():
    r = map_easing("cubic-bezier(0.1, 0.9, 0.2, 1)", [])
    assert r["klass"] == "cubic-bezier" and r["certified"] is True
    assert r["bezier"] == [0.1, 0.9, 0.2, 1.0]


def test_map_easing_prefers_nonlinear_keyframe_over_linear_timing():
    # CSS animations often report getTiming().easing == "linear" with the real
    # animation-timing-function on the keyframes.
    r = map_easing("linear", ["ease-out", "linear"])
    assert r["klass"] == "ease-out" and r["certified"] is True


def test_map_easing_all_linear_is_linear():
    r = map_easing("linear", ["linear"])
    assert r == {"klass": "linear", "bezier": [0, 0, 1, 1],
                 "certified": True, "reason": None}


def test_map_easing_steps_uncertified():
    r = map_easing("steps(4, end)", [])
    assert r == {"klass": "steps", "bezier": None,
                 "certified": False, "reason": "steps()"}


def test_map_easing_mixed_keyframe_easing_uncertified():
    r = map_easing("linear", ["ease-out", "ease-in"])
    assert r["certified"] is False and r["reason"] == "mixed-keyframe-easing"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python -m pytest test_transition.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_transition'`.

- [ ] **Step 3: Write `_transition.py` with `map_easing`**

Create `scripts/_transition.py`:

```python
#!/usr/bin/env python3
"""_transition — pure core for driven-state TRANSITION capture (no browser, no I/O).

`map_easing`: map a DECLARED CSS easing (overall timing easing + per-keyframe
easings, as read from WAAPI getAnimations()) onto the project's cubic-bezier
vocabulary (_anim_core.EASINGS). `_bind_node`: bind an animation's bbox anchor to a
component-local node id. `build_transition`: assemble a content-free `transition`
for one driven State's `component`. All deterministic and unit-tested; web_states.py
wraps them with CDP I/O.

The declared law is read, not measured, so each captured law's VALUE is exact. WHICH
animations are caught is timing-sensitive (getAnimations() is a snapshot) — coverage
is best-effort, an honest ceiling, never guessed."""
from __future__ import annotations
import re

from _anim_core import EASINGS

_NAMED = {"linear", "ease", "ease-in", "ease-out", "ease-in-out"}
_CB = re.compile(r"cubic-bezier\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)")
_LINEAR = (0.0, 0.0, 1.0, 1.0)


def _close(a, b, tol):
    return all(abs(float(x) - float(y)) <= tol for x, y in zip(a, b))


def _parse_one(s):
    """('named', name) | ('bezier', (x1,y1,x2,y2)) | ('steps', s) | ('unknown', s) | None."""
    if not s:
        return None
    s = s.strip()
    if s in _NAMED:
        return ("named", s)
    m = _CB.match(s)
    if m:
        return ("bezier", tuple(float(g) for g in m.groups()))
    if s.startswith("steps") or s in ("step-start", "step-end"):
        return ("steps", s)
    return ("unknown", s)


def _to_bezier(parsed):
    kind, val = parsed
    if kind == "named":
        return tuple(float(v) for v in EASINGS[val])
    if kind == "bezier":
        return val
    return None  # unknown -> no control points


def map_easing(declared_easing, kf_easings=None, tol=0.02):
    """Map a declared easing to {klass, bezier, certified, reason}. Considers the
    overall easing AND per-keyframe easings (CSS animations report the real
    animation-timing-function on keyframes while getTiming().easing stays "linear").
    Prefers the single non-linear curve; steps()/mixed per-keyframe easing are an
    honest ceiling (certified False, never force-fit)."""
    cands = [declared_easing] + list(kf_easings or [])
    parsed = [p for p in (_parse_one(c) for c in cands) if p]
    if any(k == "steps" for k, _ in parsed):
        return {"klass": "steps", "bezier": None, "certified": False, "reason": "steps()"}
    beziers = [b for b in (_to_bezier(p) for p in parsed) if b is not None]
    non_linear = [b for b in beziers if not _close(b, _LINEAR, tol)]
    uniq = []
    for b in non_linear:
        if not any(_close(b, u, tol) for u in uniq):
            uniq.append(b)
    if not uniq:
        return {"klass": "linear", "bezier": [0, 0, 1, 1], "certified": True, "reason": None}
    if len(uniq) > 1:
        return {"klass": "cubic-bezier", "bezier": [round(v, 4) for v in uniq[0]],
                "certified": False, "reason": "mixed-keyframe-easing"}
    b = uniq[0]
    for name, pts in EASINGS.items():
        if name == "linear":
            continue
        if _close(b, pts, tol):
            return {"klass": name, "bezier": [float(v) for v in pts],
                    "certified": True, "reason": None}
    return {"klass": "cubic-bezier", "bezier": [round(v, 4) for v in b],
            "certified": True, "reason": None}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python -m pytest test_transition.py -q`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/_transition.py scripts/test_transition.py
git commit -m "feat: add _transition.map_easing (declared CSS easing -> bezier vocabulary)"
```

---

## Task 2: `_transition.py` — `_bind_node` + `build_transition` (pure)

**Files:**
- Modify: `scripts/_transition.py` (append two functions)
- Test: `scripts/test_transition.py` (append tests)

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test_transition.py`:

```python
def _component():
    # Mirrors build_component output: re-rooted nodes with component-local ids.
    return {"n_nodes": 2, "nodes": [
        {"id": 0, "role": "region", "bbox": {"x": 40, "y": 40, "w": 320, "h": 180},
         "z": 0, "sizing": None, "layout": None,
         "colors": {"bg": "rgb(18, 52, 86)", "fg": None, "border": None},
         "parent": None, "mount": {"role": "box", "bbox": {"x": 0, "y": 0, "w": 1000, "h": 400},
                                   "colors": {"bg": "rgba(0,0,0,0)", "fg": None, "border": None}}},
        {"id": 1, "role": "text", "bbox": {"x": 50, "y": 50, "w": 300, "h": 24},
         "z": 0, "sizing": None, "layout": None,
         "colors": {"bg": None, "fg": "rgb(200,200,200)", "border": None},
         "parent": 0, "mount": None}]}


def test_bind_node_matches_nearest_component_node_by_bbox():
    c = _component()
    # bbox over node 0's box (center ~200,130)
    assert _bind_node({"x": 41, "y": 41, "w": 318, "h": 178}, c) == 0
    # bbox over node 1's box (center ~200,62)
    assert _bind_node({"x": 50, "y": 50, "w": 300, "h": 24}, c) == 1


def test_bind_node_returns_none_when_no_node_within_radius():
    c = _component()
    assert _bind_node({"x": 900, "y": 900, "w": 10, "h": 10}, c) is None


def test_build_transition_none_when_empty_or_no_component():
    c = _component()
    assert build_transition([], c) is None
    assert build_transition([{"duration": 240, "iterations": 1, "bbox": None,
                              "easing": "ease-out", "props": ["opacity"]}], None) is None


def test_build_transition_binds_and_maps_law():
    c = _component()
    raw = [{"duration": 240.0, "delay": 0, "easing": "linear",
            "kfEasings": ["ease-out", "linear"], "iterations": 1,
            "props": ["transform", "opacity"],
            "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}, "playState": "running"}]
    t = build_transition(raw, c)
    assert t["n_anims"] == 1
    a = t["anims"][0]
    assert a["node"] == 0
    assert a["props"] == ["opacity", "transform"]   # sorted
    assert a["duration_ms"] == 240.0 and a["delay_ms"] == 0
    assert a["easing"]["klass"] == "ease-out" and a["certified"] is True
    assert a["reason"] is None


def test_build_transition_skips_infinite_and_zero_duration():
    c = _component()
    raw = [{"duration": 240, "iterations": None, "easing": "ease-out",  # ambient loop
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}},
           {"duration": 0, "iterations": 1, "easing": "ease-out",        # no motion
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    assert build_transition(raw, c) is None


def test_build_transition_unbound_reason_when_no_node_match():
    c = _component()
    raw = [{"duration": 240, "delay": 0, "easing": "ease-out", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 900, "y": 900, "w": 10, "h": 10}}]
    t = build_transition(raw, c)
    assert t["anims"][0]["node"] is None
    assert t["anims"][0]["reason"] == "unbound"
    assert t["anims"][0]["certified"] is True   # easing law still exact


def test_build_transition_content_free_keys_only():
    c = _component()
    raw = [{"duration": 240, "delay": 0, "easing": "ease-out", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    a = build_transition(raw, c)["anims"][0]
    assert set(a.keys()) == {"node", "props", "duration_ms", "delay_ms",
                             "easing", "certified", "reason"}
    assert set(a["easing"].keys()) == {"klass", "bezier"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python -m pytest test_transition.py -q`
Expected: FAIL — `ImportError: cannot import name '_bind_node'` (or the new tests error).

- [ ] **Step 3: Append `_bind_node` + `build_transition` to `scripts/_transition.py`**

```python
def _bind_node(bbox, component, radius=24.0):
    """Bind an animation's bbox anchor to the nearest component-local node id whose
    bbox center is within `radius` px on both axes, else None. radius is tight: an
    animated element's own bbox should coincide with its component node's bbox
    (unlike match_motion's 400px band for loosely-anchored scroll motion)."""
    if not bbox or not component:
        return None
    cx = bbox["x"] + bbox["w"] / 2.0
    cy = bbox["y"] + bbox["h"] / 2.0
    best, best_d = None, None
    for n in component.get("nodes", []):
        nb = n["bbox"]
        nx = nb["x"] + nb["w"] / 2.0
        ny = nb["y"] + nb["h"] / 2.0
        if abs(cx - nx) <= radius and abs(cy - ny) <= radius:
            d = abs(cx - nx) + abs(cy - ny)
            if best_d is None or d < best_d:
                best, best_d = n["id"], d
    return best


def build_transition(anims_raw, component, radius=24.0):
    """Assemble a content-free `transition` for one driven State's `component` from
    raw WAAPI getAnimations() records. Returns {"n_anims": N, "anims": [...]} or None
    when nothing animated (after filtering ambient infinite loops and zero-duration
    no-ops). Each anim carries: node (component-local id | None), props (sorted CSS
    property NAMES), duration_ms, delay_ms, easing {klass, bezier}, certified, reason.

    `reason` reports the easing disqualifier (steps()/mixed-keyframe-easing) when the
    law is not bezier-representable; otherwise "unbound" when no component node
    matched the anchor; otherwise None. `certified` reflects the EASING law only (an
    unbound but bezier-representable law is still exact)."""
    if not anims_raw or not component:
        return None
    anims = []
    for a in anims_raw:
        if a.get("iterations") is None:   # JSON-null == non-finite == ambient loop
            continue
        dur = a.get("duration")
        if not dur or dur <= 0:           # zero/None duration == no real motion
            continue
        easing = map_easing(a.get("easing"), a.get("kfEasings"))
        node = _bind_node(a.get("bbox"), component, radius)
        reason = easing["reason"]
        if reason is None and node is None:
            reason = "unbound"
        anims.append({
            "node": node,
            "props": sorted(set(a.get("props") or [])),
            "duration_ms": dur,
            "delay_ms": a.get("delay", 0) or 0,
            "easing": {"klass": easing["klass"], "bezier": easing["bezier"]},
            "certified": easing["certified"],
            "reason": reason,
        })
    if not anims:
        return None
    return {"n_anims": len(anims), "anims": anims}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python -m pytest test_transition.py -q`
Expected: 13 passed (7 from Task 1 + 6 here).

- [ ] **Step 5: Commit**

```bash
git add scripts/_transition.py scripts/test_transition.py
git commit -m "feat: add _transition.build_transition + _bind_node (bind reveal law to component node)"
```

---

## Task 3: Wire transition capture into `web_states.py`

**Files:**
- Modify: `scripts/web_states.py`

Reference — the current per-trigger loop body (around lines 145-160):

```python
            try:
                pre, _, _ = _snapshot_skeleton(ev, args.url)  # fresh baseline: no cross-attribution
                opened = ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                if not opened:
                    continue
                time.sleep(0.3)  # let the reveal animate/lay out
                after, _, _ = _snapshot_skeleton(ev, args.url)
                d = diff_skeletons(pre, after)
                comp = build_component(pre, after)
                states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                               "appeared": d["appeared"], "component": comp})
                # best-effort toggle-back (re-baselining makes correctness not depend on it)
                ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                time.sleep(0.15)
            except Exception:
                continue
```

- [ ] **Step 1: Add the import**

Change line 30 from:

```python
from _states import classify_trigger, diff_skeletons, build_component
```

to:

```python
from _states import classify_trigger, diff_skeletons, build_component
from _transition import build_transition
```

- [ ] **Step 2: Add `_LIVE_WINDOW` and `_TRANSITION_JS` constants**

Immediately after the `_ESCAPE_JS = (...)` block (before `def main()`), add:

```python
# Capture the reveal animation in the LIVE window. CSS transitions/animations are
# created on the next style recalc, so reading getAnimations() in the same microtask
# as the click returns empty; wait ~1-2 frames (NOT the full settle, which would let
# a short reveal finish), THEN read. Pinned by fixtures/transition/spike_getanimations.py.
_LIVE_WINDOW = 0.05

# In-page DECLARED-law reader: per running animation, its timing (duration/delay/
# easing/iterations), per-keyframe easings, the animated CSS property NAMES (never
# values), and a bbox anchor. Content-free: numbers + easing strings + property names
# + geometry. iterations non-finite -> null (ambient loop, dropped downstream).
_TRANSITION_JS = r"""
(() => document.getAnimations().map(a => {
  const e = a.effect; if (!e || !e.getTiming) return null;
  const t = e.getTiming();
  const kfs = (e.getKeyframes && e.getKeyframes()) || [];
  const tgt = e.target;
  const r = (tgt && tgt.getBoundingClientRect) ? tgt.getBoundingClientRect() : null;
  return {
    duration: (typeof t.duration === 'number') ? t.duration : null,
    delay: t.delay || 0,
    easing: t.easing || null,
    iterations: Number.isFinite(t.iterations) ? t.iterations : null,
    kfEasings: kfs.map(k => k.easing).filter(Boolean),
    props: [...new Set(kfs.flatMap(k => Object.keys(k).filter(
             p => !['offset','easing','composite','computedOffset'].includes(p))))],
    bbox: r ? {x: Math.round(r.left), y: Math.round(r.top),
               w: Math.round(r.width), h: Math.round(r.height)} : null,
    playState: a.playState
  };
}).filter(Boolean))()
"""
```

- [ ] **Step 3: Reorder the loop body to capture LIVE, then attach `transition`**

Replace the loop body (the `try:` block shown in the reference above) with:

```python
            try:
                pre, _, _ = _snapshot_skeleton(ev, args.url)  # fresh baseline: no cross-attribution
                opened = ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                if not opened:
                    continue
                time.sleep(_LIVE_WINDOW)               # ~1-2 frames: reveal now running
                trans_raw = ev.ev(_TRANSITION_JS) or []  # read declared law WHILE animating
                time.sleep(0.3)                        # let the reveal finish laying out
                after, _, _ = _snapshot_skeleton(ev, args.url)
                d = diff_skeletons(pre, after)
                comp = build_component(pre, after)
                trans = build_transition(trans_raw, comp) if comp else None
                states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                               "appeared": d["appeared"], "component": comp,
                               "transition": trans})
                # best-effort toggle-back (re-baselining makes correctness not depend on it)
                ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                time.sleep(0.15)
            except Exception:
                continue
```

- [ ] **Step 4: Add `transitions_built` to the `--out` summary**

In the `if args.out:` branch, change the `emit_json({...})` call to add the line after `"components_built": ...`:

```python
                       "components_built": sum(1 for s in states if s["component"]),
                       "transitions_built": sum(1 for s in states if s.get("transition")),
```

- [ ] **Step 5: Update the module docstring schema example**

In the docstring (the `{"schema": "probe-states/1", ...}` example), change the state-dict line to include `transition`:

```python
   "states": [{"trigger": {"selector","kind","action"},
               "n_appeared": M, "appeared": [{"role","bbox","z"}, ...],
               "component": {"n_nodes": M, "nodes": [...]} | null,
               "transition": {"n_anims": K, "anims": [...]} | null}, ...]}
```

And append after the existing `component` paragraph:

```python
The per-state `transition` (added by _transition.build_transition) is the reveal
animation's content-free motion-law (which CSS properties animate + duration + delay
+ easing, bound to component nodes), read from the engine via getAnimations() in the
live window after the click. null when nothing animated. Coverage is best-effort (a
snapshot poll-race + JS-rAF blind spot are honest ceilings); each captured law's
value is exact. See _transition.build_transition for the shape.
```

- [ ] **Step 6: Verify the existing unit suite still passes (no regression)**

Run: `cd scripts && python -m pytest -q`
Expected: all pre-existing tests pass (web_states has no unit tests of its own; `_states`/`_transition`/firewall tests are the guard). No import errors.

- [ ] **Step 7: Commit**

```bash
git add scripts/web_states.py
git commit -m "feat: capture driven-state reveal transition live and attach to component"
```

---

## Task 4: Firewall — a `transition`-carrying states.json audits clean

**Files:**
- Modify: `scripts/test_content_firewall.py`

This re-verifies the P4 raw-token blocker (advisor #4): the `transition` adds easing strings (`cubic-bezier(...)`) and CSS property names to the on-disk states.json — confirm the firewall's text scan does not flag them.

- [ ] **Step 1: Write the failing test**

Append to `scripts/test_content_firewall.py` (uses the existing `_clean_bundle` helper and `import content_firewall as cf`):

```python
def test_audit_passes_states_with_transition(tmp_path):
    # A states.json carrying a per-state TRANSITION (reveal motion-law: CSS property
    # NAMES, numeric timings, easing strings incl. cubic-bezier, bbox anchor) must
    # audit content-free. Easing strings + property names are short structured tokens
    # the firewall's text scan does not flag (same class as rgb()/font-family). No
    # page text, no keyframe values ever enter the transition.
    d = _clean_bundle(tmp_path)
    states = {
        "schema": "probe-states/1", "url": "http://127.0.0.1/",
        "base_nodes": 10, "consent": None,
        "triggers_found": 1, "triggers_driven": 1,
        "states": [{
            "trigger": {"selector": "html > body > button:nth-of-type(1)",
                        "kind": "disclosure", "action": "click"},
            "n_appeared": 1,
            "appeared": [{"role": "region",
                          "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0}],
            "component": {"n_nodes": 1, "nodes": [
                {"id": 0, "role": "region",
                 "bbox": {"x": 40, "y": 40, "w": 320, "h": 180}, "z": 0,
                 "sizing": None, "layout": None,
                 "colors": {"bg": "rgb(18, 52, 86)", "fg": None, "border": None},
                 "parent": None, "mount": None}]},
            "transition": {"n_anims": 2, "anims": [
                {"node": 0, "props": ["opacity", "transform"],
                 "duration_ms": 240.0, "delay_ms": 0,
                 "easing": {"klass": "ease-out", "bezier": [0, 0, 0.58, 1]},
                 "certified": True, "reason": None},
                {"node": None, "props": ["opacity"],
                 "duration_ms": 180.0, "delay_ms": 0,
                 "easing": {"klass": "cubic-bezier", "bezier": [0.1, 0.9, 0.2, 1]},
                 "certified": True, "reason": "unbound"}]}}]}
    (d / "states.json").write_text(json.dumps(states, indent=2))
    assert cf.audit_bundle(d) == []
```

- [ ] **Step 2: Run the test**

Run: `cd scripts && python -m pytest test_content_firewall.py::test_audit_passes_states_with_transition -v`
Expected: PASS. (If it FAILS with a flagged-content violation, the firewall flags an easing/property token — STOP and report; do not normalize away alpha/strings without re-deciding, per the P4 lesson.)

- [ ] **Step 3: Run the whole firewall suite (no regression)**

Run: `cd scripts && python -m pytest test_content_firewall.py -q`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: verify states.json with a transition motion-law audits content-free"
```

---

## Task 5: Full suite green

**Files:** none (verification task).

- [ ] **Step 1: Run the entire unit suite**

Run: `cd scripts && python -m pytest -q`
Expected: all tests pass (prior count + 13 `_transition` + 1 firewall). No failures, no errors.

- [ ] **Step 2: If anything fails, fix it in the owning task's file and re-run.** Do not proceed to the host gate with a red suite.

---

## Task 6: Host gate — `run_transition.py` (live end-to-end)

**Files:**
- Create: `fixtures/transition/run_transition.py`
- Modify: `.gitignore`

Mirrors `fixtures/component/run_component.py`. Proves the LIVE capture: a revealed panel animated by a 240ms ease-out CSS animation yields a captured `transition` with the right duration/easing/props bound to the component node carrying the panel bg.

- [ ] **Step 1: Add the gitignore entry**

Append to `.gitignore`:

```
fixtures/transition/_out.json
```

- [ ] **Step 2: Write the host gate**

Create `fixtures/transition/run_transition.py`:

```python
#!/usr/bin/env python3
"""Host gate: web_states captures a revealed panel's reveal animation as a
content-free transition motion-law.

Deterministic, offline. Serves one page with a button (aria-expanded) whose click
reveals a display:none panel via a CSS @keyframes animation (240ms ease-out on
opacity+transform). Runs web_states (CDP, host Chrome) and asserts states[*].transition:
a non-null transition whose anim binds (node not None) to the component node carrying
the panel's known bg, with duration_ms ~= 240, easing klass certified ease-out (or its
cubic-bezier), and animated props including opacity/transform. The content-free
guarantee is proven separately by test_content_firewall.py (real cf.audit_bundle);
this gate proves the LIVE declared-law capture mechanism + the click->capture->settle
ordering."""
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

PANEL_RGB = (18, 52, 86)  # #123456-equivalent panel bg; matched via parse_color (format-robust)

_PAGE = """<!doctype html><meta charset=utf-8><title>transition-gate</title>
<style>
  body { margin: 0; font-family: sans-serif; }
  #panel { display: none; margin: 40px; width: 320px;
           background: rgb(18,52,86); color: rgb(240,240,240); padding: 16px; }
  #panel.open { display: block; animation: reveal 240ms ease-out both; }
  @keyframes reveal { from { opacity: 0; transform: translateY(8px); }
                      to   { opacity: 1; transform: translateY(0); } }
</style>
<body>
  <button id=btn aria-expanded="false" aria-controls="panel">Open</button>
  <div id=panel role="region"><p id=lbl>Revealed label</p></div>
  <script>
    const b = document.getElementById('btn'), p = document.getElementById('panel');
    b.addEventListener('click', () => {
      p.classList.remove('open'); void p.offsetWidth;   // restart animation each open
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
    out = ROOT / "fixtures" / "transition" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def _check(obj) -> bool:
    states = obj.get("states") or []
    # find the state whose component carries the panel bg AND has a transition
    target = None
    for s in states:
        comp = s.get("component")
        if not comp:
            continue
        if any(parse_color((n.get("colors") or {}).get("bg")) == PANEL_RGB
               for n in comp["nodes"]):
            target = s
            break
    if target is None:
        print("GATE FAIL: no component carried the panel bg", PANEL_RGB)
        return False
    trans = target.get("transition")
    if not trans or not trans.get("anims"):
        print("GATE FAIL: revealed panel produced no transition", json.dumps(trans))
        return False
    # at least one anim must bind to a component node, run ~240ms, ease-out-ish, on
    # opacity/transform
    comp_ids = {n["id"] for n in target["component"]["nodes"]}
    ok = False
    for a in trans["anims"]:
        bound = a["node"] in comp_ids
        dur_ok = a["duration_ms"] is not None and 200 <= a["duration_ms"] <= 280
        props_ok = bool({"opacity", "transform"} & set(a.get("props") or []))
        ease_ok = a["certified"] and a["easing"]["bezier"] is not None
        if bound and dur_ok and props_ok and ease_ok:
            ok = True
            print("transition ok: node=%s dur=%s klass=%s props=%s"
                  % (a["node"], a["duration_ms"], a["easing"]["klass"], a["props"]))
            break
    if not ok:
        print("GATE FAIL: no bound, ~240ms, certified opacity/transform anim;",
              json.dumps(trans["anims"]))
        return False
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
        print("GATE PASS: revealed panel's reveal animation captured as a content-free "
              "transition motion-law (bound to the component, certified easing).")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 3: Controller runs the gate on host**

Run on host Bash with `dangerouslyDisableSandbox=true`:
`python fixtures/transition/run_transition.py`
Expected: `GATE PASS` (exit 0), with a `transition ok:` line showing a bound node, `dur≈240`, `klass` ∈ {`ease-out`, `cubic-bezier`}, props including opacity/transform.

If `GATE FAIL` with "no transition": the `_LIVE_WINDOW` from Task 0 was too long/short — adjust the constant in `web_states.py` to the spike's pinned value and re-run.

- [ ] **Step 4: Commit**

```bash
git add fixtures/transition/run_transition.py .gitignore
git commit -m "test: add host gate for live driven-state transition capture"
```

---

## Task 7: Update CONTEXT.md + capture-gaps record

**Files:**
- Modify: `CONTEXT.md`
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md`

- [ ] **Step 1: Update the CONTEXT.md State glossary entry**

In `CONTEXT.md`, the **State** glossary entry ends with a sentence about the driven State carrying a `component`. Append one sentence:

```
The reveal between REST and that State is captured as a content-free `transition` (the
component's revealing motion-law: which CSS properties animate + duration + delay +
easing, read from the engine's declared animation), completing the State→Transition
pair for the web substrate. Coverage of which animations are caught is best-effort
(an Honest ceiling); each captured law's value is exact.
```

- [ ] **Step 2: Append a results record to the capture-gaps doc**

Append a new section to `docs/plans/probe-runner-engine-capture-gaps.md`:

```markdown
## §C9-R-P5 — Results: driven-state transition capture LANDED (2026-05-31)

Second roadmap item after the §C9 ladder; completes CONTEXT.md principle #3 (component
= States + Transitions) for the web substrate. P4 captured each driven State as a
content-free `component`; P5 captures the reveal `transition` (the motion-law between
REST and that State).

- **Mechanism:** WAAPI `document.getAnimations()` read in the live window (≈1-2 frames)
  after the click, over the existing `ev()` transport — no new CDP plumbing. New pure
  core `_transition.py` (`map_easing`/`_bind_node`/`build_transition`) maps the declared
  CSS easing onto `_anim_core.EASINGS` and binds each anim to a component-local node by
  bbox. `web_states` reorders the loop to click → capture LIVE → settle → snapshot.
- **Content-free:** CSS property NAMES (never values) + numeric timings + easing strings
  + bbox. Re-verified by `test_content_firewall.py` (real `cf.audit_bundle`).
- **Honest ceilings:** coverage is best-effort (getAnimations() snapshot poll-race; JS-rAF
  motion with no WAAPI/CSS object is invisible); `steps()`/mixed-per-keyframe easing →
  `certified:false`, never force-fit. Each captured law's value is exact.
- **Verified:** pure-core unit tests + firewall test + host gate (`fixtures/transition/
  run_transition.py`, GATE PASS on a 240ms ease-out reveal).

**§C9 ladder + roadmap status:** P0/P1/P2/P3-G1/P3-G6 (the §C9 ladder) + per-state
component capture (P4) + driven-state transition capture (P5) all landed. Remaining
roadmap (not started): later acquisition gaps as they surface, iOS/Android/Flutter
native.
```

- [ ] **Step 3: Commit**

```bash
git add CONTEXT.md docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record driven-state transition capture (§C9-R-P5) landed"
```

---

## Final review

After all tasks: dispatch a final code reviewer over the whole implementation (`_transition.py`, `web_states.py` diff, both test files, both fixtures). Confirm: content-free invariant held (no page text/values in the transition), `n_anims == len(anims)`, easing mapping has no force-fit, the loop ordering captures live, schema stayed `probe-states/1`. Then report completion — do NOT push.
```
