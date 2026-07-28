# Mode C1 — Event/Time Animation Timelines (`events.json`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture every non-scroll animation a page fires — load/entrance, click-triggered, looping — via `getAnimations()`, and serialize them into a new content-free bundle artifact **`events.json`** so a clone replays stagger cascades and loops faithfully (not in-sync, not one-shot).

**Architecture:** A shared pure core `_getanims.py` (normalize + stagger-grouping, no I/O) reused by a new live verb `web_getanims.py` and by `web_flipbook.py` (which already reads `getAnimations`). The captured timelines are **selector-keyed and NOT node-bound** — they bypass `bundle_writer.match_motion` entirely, because the elements they describe (the `LoadingOverlay`, the hidden menu `Nav_nav` panel) are transient/hidden and **do not exist in the REST `skeleton.json`** (verified: skeleton nodes carry no selector and contain none of those elements — so per-node binding would silently drop all of them). `bundle_writer` gains a sixth artifact `events.json`; the content-firewall audit already scans it (selectors are mechanism, not content).

**Tech Stack:** Python 3 (stdlib + the existing `motion_adapter.parse_bezier`/`_web_eval` transport), pytest, Chrome DevTools Protocol. Canonical repo only (propagation discontinued). `PR = ~/Developer/artificial_intelligence/skills/probe-runner`.

**Why this is its own artifact (not more `motion.json` rows):**
- `motion.json` rows are **node-bound** (`match_motion` maps `anchor`→nearest REST skeleton node). Scroll/spatial movers (hero) exist at REST → bind fine. Event/time elements (load overlay, menu spans) are **absent from REST** → every such row hits `best is None → continue` and is dropped silently. That is the real reason the kasane stagger never reached the bundle.
- Event timelines are therefore **selector-keyed** (the rebuilding agent applies them to the clone's own DOM by structure, like it fills typed `slots`), and a 54-span cascade collapses to **one stagger group** (`base`/`step`/`count`) instead of 54 dead rows.

**Conventions (carried):** TDD per task (failing test → run-fail → minimal code → run-pass → commit). Single-line commit, explicit staging, NO push. Synthetic tests feed VARYING data (synthetic-green guard). `getAnimations()` is an EXACT oracle → recovered timing is `rms`-free / exact, distinct from flipbook pixel fits.

---

## File Structure

- **Create** `PR/scripts/_getanims.py` — pure core: `parse_iterations`, `normalize_animation`, `group_staggers`, `expand_stagger`. No browser, no network. The whole semantic surface, unit-tested.
- **Create** `PR/scripts/web_getanims.py` — live verb: CDP transport + load-poll + real-CDP-click trigger + document-wide `getAnimations()` enumeration (emitting per-target selector/ancestor/bbox/keyframes) → `_getanims` → `events.json`. Thin I/O over the core; `--self-test` runs the core on a bundled fixture offline.
- **Create** `PR/scripts/test_getanims.py` — unit tests for the core.
- **Modify** `PR/scripts/web_flipbook.py` — replace its inline `getAnimations` read with `_getanims` (DRY).
- **Modify** `PR/scripts/bundle_writer.py` — `assemble(..., events=None)` carries `events`; `write_bundle` writes `events.json`; `main()` gains `--events`.
- **Modify** `PR/scripts/test_bundle_writer.py` — events round-trip + the `assemble` keys-set assertion migration.

---

## events.json schema (the contract this plan produces)

A list of entries. Two `kind`s:

```jsonc
// a single time/event animation (e.g. a LoadingOverlay element fading)
{"kind":"single","selector":".LoadingOverlay_brandLogo","trigger":"load",
 "prop":"opacity","from":1.0,"to":0.0,
 "duration":800,"delay":200,"easing":"ease-out","cubic_bezier":null,
 "iterations":1,"direction":"normal","fill":"both"}

// a stagger cascade collapsed to ONE entry (e.g. the 54-span menu reveal)
{"kind":"stagger","container":".Nav_nav__dtTHU","child":"span","count":54,
 "trigger":"click:.Header_el__lSXpJ","prop":"opacity","from":0.0,"to":1.0,
 "duration":1000,"easing":"cubic-bezier(0.76,0,0.24,1)","cubic_bezier":[0.76,0,0.24,1],
 "delay":{"base":0.0,"step":5.66,"total":300.0},
 "iterations":1,"direction":"normal","fill":"both"}
```

`trigger` ∈ {`"load"`, `"click:<selector>"`, `"hover:<selector>"`, `"none"`}. `iterations` is a number, or the string `"infinite"` (NEVER `float('inf')` — JS `JSON.parse` rejects `Infinity`). Timing is in **milliseconds**.

---

## Task 1: `_getanims` pure core — normalize, group staggers, expand

**Files:**
- Create: `PR/scripts/_getanims.py`
- Test: `PR/scripts/test_getanims.py`

- [ ] **Step 1: Write the failing test**

```python
# test_getanims.py
import _getanims as g


def _raw(sel, prop, frm, to, dur, delay, easing, anc, *, iters=1, child=None):
    """A raw getAnimations entry shaped like web_getanims emits (one keyframed prop)."""
    return {"selector": sel, "ancestor": anc, "child": child, "prop": prop,
            "from": frm, "to": to, "duration": dur, "delay": delay,
            "easing": easing, "iterations": iters, "direction": "normal", "fill": "both"}


def test_parse_iterations_infinite_is_string_not_inf():
    assert g.parse_iterations(1) == 1
    assert g.parse_iterations(3.0) == 3.0
    assert g.parse_iterations(None) == 1            # default
    assert g.parse_iterations(float("inf")) == "infinite"
    assert g.parse_iterations("Infinity") == "infinite"


def test_normalize_single_opacity():
    n = g.normalize_animation(
        _raw(".LoadingOverlay_brandLogo", "opacity", 1, 0, 800, 200, "ease-out", anc=None))
    assert n["kind"] == "single"
    assert n["selector"] == ".LoadingOverlay_brandLogo"
    assert (n["from"], n["to"], n["duration"], n["delay"]) == (1.0, 0.0, 800, 200)
    assert n["easing"] == "ease-out" and n["cubic_bezier"] is None
    assert n["iterations"] == 1


def test_normalize_parses_cubic_bezier():
    n = g.normalize_animation(
        _raw("span", "opacity", 0, 1, 1000, 0, "cubic-bezier(0.76,0,0.24,1)", anc=".Nav_nav__dtTHU"))
    assert n["cubic_bezier"] == [0.76, 0.0, 0.24, 1.0]


def test_group_staggers_collapses_a_cascade():
    # 5 spans, same container/prop/dur/easing, delays 0,20,40,60,80 -> ONE stagger.
    anc, child = ".Nav_nav__dtTHU", "span"
    raws = [g.normalize_animation(
        _raw("span", "opacity", 0, 1, 1000, d, "cubic-bezier(0.76,0,0.24,1)", anc=anc, child=child))
        for d in (0, 20, 40, 60, 80)]
    # plus an unrelated single (different container) that must NOT be grouped
    raws.append(g.normalize_animation(
        _raw(".LoadingOverlay_brandLogo", "opacity", 1, 0, 800, 200, "ease-out", anc=None)))
    out = g.group_staggers(raws, trigger="click:.Header_el__lSXpJ")
    staggers = [e for e in out if e["kind"] == "stagger"]
    singles = [e for e in out if e["kind"] == "single"]
    assert len(staggers) == 1 and len(singles) == 1
    s = staggers[0]
    assert s["container"] == anc and s["child"] == "span" and s["count"] == 5
    assert s["delay"] == {"base": 0.0, "step": 20.0, "total": 80.0}
    assert s["trigger"] == "click:.Header_el__lSXpJ"
    assert s["cubic_bezier"] == [0.76, 0.0, 0.24, 1.0]
    assert singles[0]["trigger"] == "click:.Header_el__lSXpJ"  # trigger applied to all


def test_expand_stagger_round_trips_per_index_delays():
    s = {"kind": "stagger", "count": 4, "delay": {"base": 0.0, "step": 100.0, "total": 300.0}}
    assert g.expand_stagger(s) == [0.0, 100.0, 200.0, 300.0]


def test_group_keeps_small_clusters_as_singles():
    # only 2 members -> below the stagger threshold (3) -> stay singles, not a group.
    raws = [g.normalize_animation(
        _raw("span", "opacity", 0, 1, 1000, d, "ease-out", anc=".X", child="span")) for d in (0, 20)]
    out = g.group_staggers(raws, trigger="none")
    assert all(e["kind"] == "single" for e in out) and len(out) == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named '_getanims'`

- [ ] **Step 3: Write minimal implementation**

```python
# _getanims.py
#!/usr/bin/env python3
"""_getanims — pure normalisation + stagger-grouping for getAnimations() captures.

No browser, no network: web_getanims.py (live) and web_flipbook.py feed raw
getAnimations entries through here. A raw entry is one keyframed property of one
Animation with its target selector, an `ancestor` (nearest stable container
selector), an optional `child` tag, from/to values, duration/delay (ms), easing,
iterations, direction, fill. Output is the events.json contract: `single` entries
and `stagger` groups (a cascade of N siblings sharing timing, collapsed to base/
step/count). getAnimations is an EXACT oracle, so no rms here."""
from __future__ import annotations

from motion_adapter import parse_bezier

STAGGER_MIN = 3  # a cascade needs >= this many siblings to collapse into a group


def parse_iterations(v):
    """Iteration count → number, or the string 'infinite'. Never float('inf')
    (invalid JSON for JS consumers)."""
    if v is None:
        return 1
    if v == "Infinity" or (isinstance(v, float) and v == float("inf")):
        return "infinite"
    return v


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return v


def normalize_animation(raw):
    """One raw getAnimations property → a normalised `single` entry."""
    return {
        "kind": "single",
        "selector": raw.get("selector"),
        "ancestor": raw.get("ancestor"),
        "child": raw.get("child"),
        "prop": raw.get("prop"),
        "from": _num(raw.get("from")),
        "to": _num(raw.get("to")),
        "duration": raw.get("duration"),
        "delay": raw.get("delay"),
        "easing": raw.get("easing"),
        "cubic_bezier": parse_bezier(raw.get("easing")),
        "iterations": parse_iterations(raw.get("iterations")),
        "direction": raw.get("direction") or "normal",
        "fill": raw.get("fill") or "none",
    }


def _cluster_key(e):
    # siblings of one cascade share everything but their delay (and exact selector).
    return (e["ancestor"], e["child"], e["prop"], e["duration"],
            e["easing"], e["from"], e["to"])


def group_staggers(entries, trigger):
    """Collapse cascades (>= STAGGER_MIN siblings sharing _cluster_key, varying
    delay) into one `stagger` group; everything else stays a `single`. `trigger`
    is stamped on every emitted entry."""
    buckets = {}
    order = []
    for e in entries:
        k = _cluster_key(e)
        if k not in buckets:
            buckets[k] = []
            order.append(k)
        buckets[k].append(e)

    out = []
    for k in order:
        members = buckets[k]
        groupable = (len(members) >= STAGGER_MIN and members[0]["child"]
                     and members[0]["ancestor"])
        if not groupable:
            for e in members:
                out.append({**e, "trigger": trigger})
            continue
        delays = sorted(float(m["delay"] or 0) for m in members)
        base, total = delays[0], delays[-1]
        n = len(members)
        step = round((total - base) / (n - 1), 2) if n > 1 else 0.0
        first = members[0]
        out.append({
            "kind": "stagger",
            "container": first["ancestor"],
            "child": first["child"],
            "count": n,
            "trigger": trigger,
            "prop": first["prop"],
            "from": first["from"],
            "to": first["to"],
            "duration": first["duration"],
            "easing": first["easing"],
            "cubic_bezier": parse_bezier(first["easing"]),
            "delay": {"base": round(base, 2), "step": step, "total": round(total, 2)},
            "iterations": first["iterations"],
            "direction": first["direction"],
            "fill": first["fill"],
        })
    return out


def expand_stagger(group):
    """A stagger group → the per-index delay list it encodes (round-trip helper
    the rebuilding agent uses to wire the cascade)."""
    d = group["delay"]
    return [round(d["base"] + i * d["step"], 2) for i in range(group["count"])]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py -v`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/_getanims.py scripts/test_getanims.py
git -C "$PR" commit -m "feat(_getanims): normalize getAnimations + collapse cascades to stagger groups"
```

---

## Task 2: `web_getanims.py` live verb (sweep → events.json)

**Files:**
- Create: `PR/scripts/web_getanims.py`
- Test: `PR/scripts/test_getanims.py` (add a `--self-test`/offline build test)

- [ ] **Step 1: Write the failing test** (the offline-buildable path — no browser)

```python
# append to test_getanims.py
import web_getanims as wg


def test_build_events_from_raw_sweep_offline():
    # the pure assembly web_getanims uses after the live capture: raw sweep dict
    # (what the in-page JS returns) -> events list. No browser.
    sweep = {"trigger": "click:.Header_el__lSXpJ", "anims": [
        {"selector": "span", "ancestor": ".Nav_nav__dtTHU", "child": "span",
         "prop": "opacity", "from": 0, "to": 1, "duration": 1000, "delay": d,
         "easing": "cubic-bezier(0.76,0,0.24,1)", "iterations": 1,
         "direction": "normal", "fill": "both"} for d in (0, 20, 40, 60)]}
    events = wg.build_events(sweep)
    assert len(events) == 1 and events[0]["kind"] == "stagger"
    assert events[0]["count"] == 4 and events[0]["container"] == ".Nav_nav__dtTHU"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py::test_build_events_from_raw_sweep_offline -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'web_getanims'`

- [ ] **Step 3: Write minimal implementation**

```python
# web_getanims.py
#!/usr/bin/env python3
"""web_getanims — enumerate EVERY animation on a page via getAnimations() and
serialise the non-scroll ones (load entrances, click/hover-triggered reveals,
loops) to events.json. This is the auto-discovery sweep Mode C1 productises:
web_flipbook tracks ONE element you name; this sweeps the whole document.

Triggers: --reload (poll the load entrance), --click <sel> (real CDP input),
default (read whatever is animating now). The in-page JS reads each Animation's
target selector, a stable ancestor container, child tag, the keyframed property's
from/to, duration/delay/iterations/direction/fill, and the easing — then the pure
_getanims core normalises and collapses cascades into stagger groups."""
from __future__ import annotations

import argparse
import json
import time

from _common import emit_json, die
from _web_eval import resolve_web_eval, navigate, add_transport_args
import _getanims as G

# Self-contained in-page expression: document-wide getAnimations() → raw entries.
# One entry per (animation, keyframed property). Selector + nearest ancestor with
# a class give the rebuilding agent structural hooks; class names are MECHANISM.
SWEEP_JS = r"""(function(){
  function cls(t){if(!t||!t.getAttribute)return null;var c=t.getAttribute('class');
    return c?('.'+c.trim().split(/\s+/).slice(0,3).join('.')):t.tagName.toLowerCase();}
  function anc(t){var e=t;while(e&&e.getAttribute){var c=e.getAttribute('class');
    if(c&&c.trim())return cls(e);e=e.parentElement;}return null;}
  var out=[];
  document.getAnimations().forEach(function(a){
    var e=a.effect; if(!e||!e.target) return; var t=e.target;
    var tm=e.getTiming(), ct=e.getComputedTiming(); var kf=[];
    try{kf=e.getKeyframes()||[];}catch(_){}
    var props={};
    kf.forEach(function(k){for(var p in k){
      if(['offset','computedOffset','easing','composite'].indexOf(p)<0){
        (props[p]=props[p]||[]).push(k[p]);}}});
    Object.keys(props).forEach(function(p){
      var vs=props[p];
      out.push({selector:cls(t), ancestor:anc(t.parentElement||t), child:t.tagName.toLowerCase(),
        prop:p, from:vs[0], to:vs[vs.length-1], duration:ct.duration, delay:tm.delay,
        easing:tm.easing, iterations:(ct.iterations===Infinity?'Infinity':ct.iterations),
        direction:tm.direction, fill:tm.fill, playState:a.playState});});
  });
  return {scrollY:window.scrollY, anims:out};
})()"""


def build_events(sweep):
    """Pure: raw sweep dict ({trigger, anims:[...]}) → events.json list.
    Drops scroll-driven entries (those belong in motion.json via web_anim)."""
    trigger = sweep.get("trigger", "none")
    norm = [G.normalize_animation(a) for a in sweep.get("anims", [])]
    return G.group_staggers(norm, trigger=trigger)


def _real_click(ev, sel):
    c = ev.ev("(function(){var el=document.querySelector(%s);if(!el)return null;"
              "var r=el.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2};})()"
              % json.dumps(sel))
    if not c:
        die("trigger selector not found: " + sel)
    for typ in ("mousePressed", "mouseReleased"):
        ev.sess.send("Input.dispatchMouseEvent",
                     {"type": typ, "x": c["x"], "y": c["y"], "button": "left", "clickCount": 1})


def _poll_sweep(ev, seconds, fps):
    """Reload + poll getAnimations across the entrance window; merge unique anims
    (by selector+prop+delay) seen RUNNING. Raw CDP send so a nav race yields {}
    instead of aborting."""
    seen = {}
    ev.sess.send("Page.enable", {})
    ev.sess.send("Page.reload", {"ignoreCache": False})
    t0 = time.time()
    while time.time() - t0 < seconds:
        try:
            r = ev.sess.send("Runtime.evaluate", {"expression": SWEEP_JS,
                             "returnByValue": True, "awaitPromise": False})
            v = r.get("result", {}).get("value") if "exceptionDetails" not in r else None
        except Exception:
            v = None
        if v:
            for a in v.get("anims", []):
                seen[(a.get("selector"), a.get("prop"), a.get("delay"))] = a
        time.sleep(1.0 / fps)
    return list(seen.values())


def main() -> int:
    p = argparse.ArgumentParser(prog="web_getanims.py",
                                description="Sweep getAnimations() → events.json")
    add_transport_args(p)
    p.add_argument("--reload", action="store_true", help="reload + poll the load entrance")
    p.add_argument("--click", help="selector to real-click as the trigger, then sweep")
    p.add_argument("--seconds", type=float, default=2.5, help="entrance poll window")
    p.add_argument("--fps", type=float, default=12, help="entrance poll rate")
    p.add_argument("--settle", type=float, default=0.18, help="s after click before sweep")
    p.add_argument("--self-test", action="store_true", help="offline core smoke, no browser")
    p.add_argument("--out", default=None)
    args = p.parse_args()

    if args.self_test:
        demo = {"trigger": "click:.x", "anims": [
            {"selector": "span", "ancestor": ".grp", "child": "span", "prop": "opacity",
             "from": 0, "to": 1, "duration": 1000, "delay": d,
             "easing": "cubic-bezier(0.76,0,0.24,1)", "iterations": 1,
             "direction": "normal", "fill": "both"} for d in (0, 20, 40, 60, 80)]}
        ev = build_events(demo)
        assert ev and ev[0]["kind"] == "stagger" and ev[0]["count"] == 5, ev
        emit_json({"ok": True, "self_test": "pass", "events": ev})
        return 0

    engine, ev, device = resolve_web_eval(args)
    try:
        if args.url:
            navigate(ev, engine, args.url)
        if args.reload:
            anims = _poll_sweep(ev, args.seconds, args.fps)
            trigger = "load"
        else:
            if args.click:
                _real_click(ev, args.click)
                time.sleep(args.settle)
                trigger = "click:" + args.click
            else:
                trigger = "none"
            v = ev.ev(SWEEP_JS)
            anims = (v or {}).get("anims", [])
        events = build_events({"trigger": trigger, "anims": anims})
    finally:
        ev.close()

    payload = {"ok": True, "device": device, "trigger": trigger,
               "raw_count": len(anims), "events": events}
    if args.out:
        with open(args.out, "w") as f:
            json.dump(events, f, indent=2)
        payload["out"] = args.out
    emit_json(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run test + offline self-test**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py -v && python3 web_getanims.py --self-test`
Expected: pytest PASS (7 tests); self-test prints `"self_test": "pass"`.

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/web_getanims.py scripts/test_getanims.py
git -C "$PR" commit -m "feat(web_getanims): getAnimations sweep verb → events.json (load/click triggers, --self-test)"
```

---

## Task 3: DRY — route `web_flipbook`'s getAnimations read through `_getanims`

**Files:**
- Modify: `PR/scripts/web_flipbook.py`
- Test: `PR/scripts/test_getanims.py`

`web_flipbook` already embeds a `getAnimations({subtree:true})` reader (its `GT_JS`). Keep its element-scoped ground-truth behaviour, but expose the per-property normalisation via the shared core so the two verbs cannot drift in how they read iterations/easing.

- [ ] **Step 1: Write the failing test**

```python
# append to test_getanims.py
def test_normalize_handles_infinite_iterations_from_raw():
    # the flipbook/getanims shared path must turn an Infinity iteration into the
    # JSON-safe string, never float('inf').
    n = g.normalize_animation({"selector": ".loader", "ancestor": None, "child": "div",
                               "prop": "opacity", "from": 0, "to": 1, "duration": 1200,
                               "delay": 0, "easing": "linear", "iterations": "Infinity",
                               "direction": "alternate", "fill": "both"})
    assert n["iterations"] == "infinite" and n["direction"] == "alternate"
```

- [ ] **Step 2: Run to verify it fails or passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py::test_normalize_handles_infinite_iterations_from_raw -v`
Expected: PASS (core already handles it — this test pins the shared contract before the refactor).

- [ ] **Step 3: Refactor `web_flipbook.py`**

At the top of `web_flipbook.py`, after its existing imports, add:

```python
import _getanims as _G  # shared getAnimations normalisation (DRY with web_getanims)
```

Find where `web_flipbook` stores the getAnimations ground truth into its result (the `"getAnimations": gt` entry in the emitted dict) and normalise iteration safety through the shared helper so a looping animation never serialises `Infinity`:

```python
        gt_norm = gt
        if isinstance(gt, list):
            for a in gt:
                if isinstance(a, dict) and "iterations" in a:
                    a["iterations"] = _G.parse_iterations(a["iterations"])
```

and emit `gt_norm` in place of `gt` in the result dict.

- [ ] **Step 4: Run the flipbook + getanims suites**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py test_web_flipbook.py -v` (if `test_web_flipbook.py` exists; otherwise just `test_getanims.py`)
Expected: PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/web_flipbook.py scripts/test_getanims.py
git -C "$PR" commit -m "refactor(web_flipbook): share _getanims iteration normalisation (no Infinity in output)"
```

---

## Task 4: `bundle_writer` writes `events.json`; firewall audits it

**Files:**
- Modify: `PR/scripts/bundle_writer.py`
- Test: `PR/scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing test**

```python
# append to test_bundle_writer.py
def test_assemble_and_write_events_json(tmp_path):
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "box", "bbox": {"x": 0, "y": 0, "w": 50, "h": 20}}]}
    events = [
        {"kind": "single", "selector": ".LoadingOverlay_brandLogo", "trigger": "load",
         "prop": "opacity", "from": 1.0, "to": 0.0, "duration": 800, "delay": 200,
         "easing": "ease-out", "cubic_bezier": None, "iterations": 1,
         "direction": "normal", "fill": "both"},
        {"kind": "stagger", "container": ".Nav_nav__dtTHU", "child": "span", "count": 54,
         "trigger": "click:.Header_el__lSXpJ", "prop": "opacity", "from": 0.0, "to": 1.0,
         "duration": 1000, "easing": "cubic-bezier(0.76,0,0.24,1)",
         "cubic_bezier": [0.76, 0, 0.24, 1], "delay": {"base": 0.0, "step": 5.66, "total": 300.0},
         "iterations": 1, "direction": "normal", "fill": "both"},
    ]
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, events=events)
    assert bundle["events"] == events
    bw.write_bundle(bundle, str(tmp_path))           # must NOT raise ContentLeak
    import os, json
    assert os.path.exists(os.path.join(str(tmp_path), "events.json"))
    on_disk = json.load(open(os.path.join(str(tmp_path), "events.json")))
    assert on_disk[1]["delay"]["total"] == 300.0     # stagger survived round-trip
    assert on_disk[0]["selector"] == ".LoadingOverlay_brandLogo"  # class = mechanism, audit-clean


def test_assemble_events_default_empty():
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1, "h": 1, "dpr": 1}, "page": {"h": 1}, "nodes": []}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    assert bundle["events"] == []                    # back-compat: omitted → empty
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_bundle_writer.py -k events -v`
Expected: FAIL — `assemble()` has no `events` kwarg / `bundle["events"]` KeyError.

- [ ] **Step 3: Modify `bundle_writer.py`**

Change the `assemble` signature to accept events (keyword, default None for back-compat):

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, events=None):
```

In `assemble`'s return dict, add the events entry (after `"manifest": manifest,`):

```python
        "manifest": manifest,
        "events": list(events) if events else [],
```

In `write_bundle`, write the artifact BEFORE the audit (so the audit also scans it). Add after the `manifest.json` write and BEFORE the `audit_bundle` call:

```python
    (root / "events.json").write_text(json.dumps(bundle.get("events", []), indent=2))
```

In `main()`, add the flag + load and pass it:

```python
    p.add_argument("--events", default=None,
                   help="events.json from web_getanims (load/time/loop timelines); omitted -> none")
```

and where motion is loaded, load events similarly, then pass `events=events_rows` to `assemble`:

```python
    events_rows = []
    if args.events:
        with open(args.events) as f:
            events_rows = json.load(f)
```
```python
    bundle = assemble(skeleton, tokens, node_colors, motion_rows,
                      meta_extra={"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                             time.gmtime())},
                      events=events_rows)
```

Migrate the existing keys-set assertion in `test_bundle_writer.py::test_assemble_builds_all_five_documents` (the bundle now has six docs):

```python
    assert set(bundle.keys()) == {"meta", "skeleton", "tokens", "motion", "manifest", "events"}
```

- [ ] **Step 4: Run bundle_writer + full suite**

Run: `cd "$PR/scripts" && python3 -m pytest test_bundle_writer.py -v && python3 -m pytest -q`
Expected: PASS (new events tests + the migrated keys assertion; whole suite green).

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/bundle_writer.py scripts/test_bundle_writer.py
git -C "$PR" commit -m "feat(bundle_writer): emit events.json (selector-keyed time/event timelines), audited"
```

---

## Task 5: Stagger fidelity — events.json firewall + round-trip guard

**Files:**
- Test: `PR/scripts/test_getanims.py`

A focused guard that the firewall accepts realistic kasane-style event selectors (hashed class names are mechanism, not prose) AND that a stagger group round-trips to per-letter delays.

- [ ] **Step 1: Write the test (passes once the prior tasks land)**

```python
# append to test_getanims.py
import json as _json
import content_firewall as cf


def test_events_json_with_real_selectors_audits_clean(tmp_path):
    (tmp_path / "assets").mkdir()
    events = [{"kind": "stagger", "container": ".Nav_nav__dtTHU", "child": "span",
               "count": 54, "trigger": "click:.Header_el__lSXpJ", "prop": "opacity",
               "from": 0.0, "to": 1.0, "duration": 1000,
               "easing": "cubic-bezier(0.76,0,0.24,1)", "cubic_bezier": [0.76, 0, 0.24, 1],
               "delay": {"base": 0.0, "step": 5.66, "total": 300.0}, "iterations": 1,
               "direction": "normal", "fill": "both"}]
    (tmp_path / "events.json").write_text(_json.dumps(events))
    (tmp_path / "skeleton.json").write_text('{"nodes":[]}')
    assert cf.audit_bundle(tmp_path) == []          # hashed class names are mechanism


def test_stagger_round_trip_matches_recorded_cascade():
    s = {"kind": "stagger", "count": 6, "delay": {"base": 0.0, "step": 60.0, "total": 300.0}}
    delays = g.expand_stagger(s)
    assert delays == [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]
    assert len(delays) == s["count"] and delays[-1] == s["delay"]["total"]
```

- [ ] **Step 2: Run to verify**

Run: `cd "$PR/scripts" && python3 -m pytest test_getanims.py -k "audits_clean or round_trip" -v`
Expected: PASS (audit returns `[]` on event selectors; expand matches). If `audits_clean` FAILS, a hashed class name is tripping a firewall rule — that is a real false-positive to fix in `content_firewall` (key-exempt the `selector`/`container`/`child` keys), NOT to work around here.

- [ ] **Step 3: (only if Step 2 surfaced a false-positive) exempt event-selector keys**

If and only if the audit flags a class selector, add `"selector"`, `"container"`, `"child"`, `"trigger"` to `content_firewall._PROSE_EXEMPT_KEYS` (they hold CSS hooks = mechanism), with a comment, and re-run. Otherwise skip.

- [ ] **Step 4: Commit**

```bash
git -C "$PR" add scripts/test_getanims.py
# include content_firewall.py only if Step 3 was needed:
# git -C "$PR" add scripts/content_firewall.py
git -C "$PR" commit -m "test(events): firewall-clean event selectors + stagger round-trip fidelity"
```

---

## Task 6: LIVE re-capture gate — fold kasane's load + menu into the bundle (the real proof)

**Files:** none (live verification + artifact refresh). REQUIRES a host Chrome with CDP.

This is the gate the synthetic tests cannot give: a synthetic sweep with matching anchors passes green while real kasane could drop everything. Run the real pipeline end-to-end and confirm the timelines land.

- [ ] **Step 1: Launch a debug Chrome**

```bash
rm -rf /tmp/kasane-cdp; mkdir -p /tmp/kasane-cdp
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9333 --user-data-dir=/tmp/kasane-cdp \
  --no-first-run --no-default-browser-check --window-size=1440,900 about:blank &
```

- [ ] **Step 2: Capture the LOAD entrance**

Run: `cd "$PR/scripts" && python3 web_getanims.py --cdp-port 9333 --url "https://kasane-keyboard.com/craftanddesign" --reload --out /tmp/ev_load.json`
Expected (verify by reading `/tmp/ev_load.json`): `single` entries for `.LoadingOverlay_*` opacity, `duration` 800, `delay` 200 / 300 on the staggered ones, `easing` `ease-out`, `trigger` `load`.

- [ ] **Step 3: Capture the MENU reveal**

Run: `cd "$PR/scripts" && python3 web_getanims.py --cdp-port 9333 --url "https://kasane-keyboard.com/craftanddesign" --click ".Header_el__lSXpJ" --out /tmp/ev_menu.json`
Expected: ONE `stagger` entry, `container` `.Nav_nav__dtTHU`-ish, `count` ≈ 54, `easing` `cubic-bezier(0.76,0,0.24,1)`, `duration` 1000, `delay.total` ≈ 300. Log `raw_count` vs grouped count — if a chunk of anims is left ungrouped, report it (no silent caps).

- [ ] **Step 4: Merge + rebuild the kasane bundle with events**

```bash
cd "$PR/scripts"
python3 -c "import json;a=json.load(open('/tmp/ev_load.json'));b=json.load(open('/tmp/ev_menu.json'));json.dump(a+b,open('/tmp/ev_all.json','w'),indent=2)"
python3 bundle_writer.py \
  --skeleton ../fixtures/kasane-rebaseline/bundle/skeleton.json \
  --tokens   ../fixtures/kasane-rebaseline/bundle/tokens.json \
  --motion   ../fixtures/kasane-rebaseline/bundle/motion.json \
  --events   /tmp/ev_all.json \
  --out /tmp/kasane_bundle_c1
```
Expected: writes without `ContentLeak`; `/tmp/kasane_bundle_c1/events.json` contains the load singles + the menu stagger group.

- [ ] **Step 5: Verify the gate, then close Chrome**

```bash
python3 -c "import json;e=json.load(open('/tmp/kasane_bundle_c1/events.json'));import collections;print('events',len(e),collections.Counter(x['kind'] for x in e));print('staggers',[(x['container'],x['count'],x['delay']) for x in e if x['kind']=='stagger'])"
pkill -f "user-data-dir=/tmp/kasane-cdp"
```
Expected: at least one `stagger` (the menu, count ≈ 54, delay total ≈ 300) and several `single` load entries. If `events` is empty or the stagger is missing, the sweep/grouping needs fixing BEFORE this task is done — do not declare success on an empty gate.

- [ ] **Step 6: Refresh the committed fixture + commit**

```bash
cp /tmp/kasane_bundle_c1/events.json "$PR/fixtures/kasane-rebaseline/bundle/events.json"
git -C "$PR" add scripts/ fixtures/kasane-rebaseline/bundle/events.json
git -C "$PR" commit -m "feat(events): fold live kasane load entrance + menu stagger into the bundle"
```

---

## Self-Review

**1. Spec coverage:**
- Capture every non-scroll animation (load/click/loop) → Task 2 `web_getanims` sweep (document-wide `getAnimations`), Task 6 live gate. ✓
- Serialize stagger faithfully → Task 1 `group_staggers` (base/step/count) + `expand_stagger`; Task 5 round-trip. ✓
- Serialize loops → `parse_iterations` → `"infinite"` string (Tasks 1, 3). ✓
- Survive transient/hidden elements (no REST node) → selector-keyed `events.json`, NOT node-bound (Task 4); this is the core fix for the silent `match_motion` drop. ✓
- Content-free → `events.json` audited by the firewall; selectors are mechanism (Task 5 asserts clean, with a fix path if a hashed class trips prose). ✓
- DRY → `_getanims` shared by `web_getanims` and `web_flipbook` (Task 3). ✓

**2. Placeholder scan:** every code step has runnable code; every command states expected output; the live gate (Task 6) names concrete expected values (delays 200/300, count ≈ 54, easing string). No TBD. ✓

**3. Type consistency:** `normalize_animation` → `single` dict; `group_staggers` → `single`/`stagger` dicts with the exact keys `events.json` (Task 4 test) and `expand_stagger` (Task 5) consume. `parse_iterations` returns number|`"infinite"` used everywhere. `assemble(..., events=None)` ↔ `bundle["events"]` ↔ `write_bundle` `events.json` ↔ `main --events`. ✓

**4. Known follow-ups (out of scope, logged — no silent caps):**
- Transform-property decomposition beyond opacity (translateX/scale/rotate from keyframe value strings) — C1 captures the timing/stagger/loop metadata for all props but only opacity gets numeric from/to; transform from/to are raw strings for the agent to interpret.
- Hover triggers (`:hover` via `CSS.forcePseudoState`) — schema has the `hover:` trigger slot; capture wiring is a later task.
- A clone-side replay/cert that fires `events.json` and diffs against source frames (closes the loop on "faithful").

---

## Execution Handoff

Plan complete and saved to `docs/plans/probe-runner-mode-c1-event-timelines.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review (spec then quality) between tasks. Tasks 1–5 are unit-testable offline; Task 6 is the live gate (needs Chrome) and should be run inline by the controller, not a subagent.
2. **Inline Execution** — execute here via executing-plans, batch with checkpoints.

Which approach?
