# P3-G6 Consent-State (Occluding-Overlay) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record a page's load-time occluding overlay (the consent-class mechanism) as a content-free `web_states` State, attempt one content-blind dismiss (Escape), and honestly record whether it cleared.

**Architecture:** A consent overlay is a `web_states` State; dismiss is a Transition reusing the G4 interaction-state machinery (CONTEXT.md / ADR-0001 principle 3). Detection is **content-blind geometry** (`position:fixed` + viewport coverage + positive z-index — never text/class/id). Dismiss is the one truly content-blind, non-destructive, non-committal gesture: an Escape keydown. We never click a button (that takes an unknown real action blind — accept-tracking / nav-away — which violates the honest-ceiling principle). The deliverable is the **honest label** (`occluding_overlay` State + `cleared: true/false` outcome), NOT a guaranteed dismiss. §C7 already proved overlays cover the DOM but do not remove it (the page behind is captured regardless), so this is the "defensive nicety" the gap doc describes, not a capture fix.

**Tech Stack:** Python 3 (stdlib only), pytest, Chrome DevTools Protocol (host Chrome). Mirrors the `_settle.py` (P3-G1) and `_states.py` (G4) patterns: a pure, I/O-injected core with unit tests, a thin CDP wrapper in the verb, and a deterministic offline host gate.

---

## Why this is small, and what "done" means

Read this before starting — it sets the scope so you don't over-build.

- **§C7 (gap doc) is load-bearing.** It empirically proved (3 awwwards sites, same-pipeline isolation) that dismissing consent makes captured node count go *down* (it removes the overlay's OWN nodes); the page DOM behind the overlay was captured all along. So G6 is NOT an acquisition fix. Its value is a content-free **record** of the occluding layer + an honest dismiss outcome.
- **Escape clears few real consent walls.** Many cookie walls deliberately ignore Escape and require reading "Accept". That is fine and expected — the honest output for those is `cleared: false`. The plan's correctness does NOT depend on a high clear rate.
- **Detection bias is UNDER-detect (documented).** Like G4's `diff_skeletons` under-count, we err toward missing an overlay (degrades to current behavior — page-behind still captured) rather than mislabelling a sticky-nav / hero / splash as an un-cleared consent State. We require `position:fixed` + coverage ≥ 0.5 + z > 0.
- **Diff direction is PRESENCE, not G4's appeared-diff.** Consent is about an overlay *disappearing*. Do NOT run `diff_skeletons` backwards. `overlay_dismissed` is a forward presence test on a re-scan.
- **Mechanism-honest naming.** Content-blind, we cannot prove an overlay is a *consent* dialog (it could be a splash / drawer / promo). The State kind is `occluding_overlay` (the mechanism), echoing P2's `iframe_uncaptured` and P3-G1's `settle`. The doc/glossary may note it's the consent-class mechanism; the data never claims certainty.

**Done = ** unit suite green (adds `test_consent.py`); `web_states` emits a `consent` key (the State, or `null` when no occluding overlay); **host gate passes BOTH cases** — an Escape-dismissable overlay (`cleared: true`) AND an Escape-ignoring overlay (`cleared: false`, present-but-not-cleared). The both-cases gate is the G6 honesty pin (the analog of P3-G1's `test_shell_trap_is_the_documented_ceiling`); a gate testing only the dismissable case fakes coverage and is a plan failure.

---

## File Structure

- **Create `scripts/_consent.py`** — pure core, no browser, no I/O. Three functions:
  - `classify_overlay(rec, *, min_coverage=0.5)` — map one scanned candidate record to an `occluding_overlay` State dict or `None`. The single source of the detection policy (fixed + coverage + z).
  - `overlay_dismissed(before, after_overlays, *, radius=24.0)` — presence test: is the recorded overlay GONE from a post-dismiss re-scan?
  - `detect_and_dismiss(scan, dismiss, sleep, *, settle_ms=0.3, min_coverage=0.5)` — I/O-injected orchestrator (the seam that makes the verb unit-testable, exactly like `_settle.adaptive_settle`). Returns the consent State dict or `None`.
- **Create `scripts/test_consent.py`** — unit tests for all three (pure; no browser).
- **Modify `scripts/web_states.py`** — add `_OVERLAY_JS` (content-blind candidate scan) + `_ESCAPE_JS` (dismiss gesture); call `detect_and_dismiss(...)` after the REST snapshot; add `consent` to `out_obj` and to the summary emit.
- **Modify `scripts/test_web_skeleton.py`** — NO. (web_states has no existing unit-test file; the testable logic lives in `_consent`, covered by `test_consent.py`. Do not add browser-dependent tests.)
- **Create `fixtures/consent/run_consent.py`** — deterministic offline host gate (both cases), mirroring `fixtures/settle/run_settle.py`.
- **Modify `docs/plans/probe-runner-engine-capture-gaps.md`** — append a `§C9-R-P3-G6` results section; repoint the live ladder pointer.
- **Modify `CONTEXT.md`** — one glossary line tying `occluding_overlay` to the consent-class mechanism under the State / Honest-ceiling principles.

The schema stays `probe-states/1` — `consent` is an additive top-level key (the P3-G1 precedent: `settle` was added without bumping `probe-skeleton/2`).

---

## Reference: existing patterns to mirror

- `scripts/_settle.py` — the I/O-injected pure-core pattern (`adaptive_settle(read, sleep, clock, ...)`). `detect_and_dismiss` follows it exactly: inject `scan`, `dismiss`, `sleep`; unit-test with fakes; the verb passes lambdas over `ev.ev(...)`.
- `scripts/_states.py` — `classify_trigger(rec)` returns a dict or `None` from a scanned record; `diff_skeletons` uses a corner/center radius of `24.0`. Reuse `radius=24.0` in `overlay_dismissed` for consistency.
- `scripts/web_states.py:30-60` — `_AFFORD_JS` (an in-page `querySelectorAll` scan returning content-free records) and `_CLICK_JS`. `_OVERLAY_JS` is the same shape; `_ESCAPE_JS` is the same shape as `_CLICK_JS`.
- `fixtures/settle/run_settle.py` — the deterministic offline `ThreadingHTTPServer` host-gate pattern (serve synthetic HTML, run the verb against `127.0.0.1:<port>`, assert on the JSON, exit 0/1).

---

### Task 1: Pure core — `classify_overlay`

**Files:**
- Create: `scripts/_consent.py`
- Test: `scripts/test_consent.py`

- [ ] **Step 1: Write the failing tests**

Create `scripts/test_consent.py`:

```python
#!/usr/bin/env python3
"""Unit tests for _consent — the pure, browser-free core of G6 occluding-overlay
(consent-class) detection and content-blind Escape dismiss."""
from _consent import classify_overlay, overlay_dismissed, detect_and_dismiss

FULL = {"x": 0, "y": 0, "w": 1280, "h": 800}


def _cand(**kw):
    base = {"position": "fixed", "z": 1000, "coverage": 1.0,
            "role": None, "bbox": FULL}
    base.update(kw)
    return base


def test_full_bleed_fixed_high_z_is_an_overlay():
    o = classify_overlay(_cand())
    assert o is not None
    assert o["kind"] == "occluding_overlay"
    assert o["coverage"] == 1.0
    assert o["z"] == 1000
    assert o["bbox"] == FULL


def test_static_hero_is_not_flagged():
    # No positioning context above content -> under-detect (safe): page-behind
    # is still captured, we just don't mislabel a hero as a consent State.
    assert classify_overlay(_cand(position="static")) is None


def test_absolute_is_not_flagged():
    # Consent backdrops are conventionally position:fixed; absolute is usually
    # in-flow layout. Require fixed -> documented under-detect direction.
    assert classify_overlay(_cand(position="absolute")) is None


def test_low_coverage_edge_banner_is_not_flagged():
    # A bottom cookie strip covers little of the viewport -> not an OCCLUDING
    # overlay. §C7: low-coverage banners don't block capture anyway.
    assert classify_overlay(_cand(coverage=0.12, bbox={"x": 0, "y": 760, "w": 1280, "h": 40})) is None


def test_no_stacking_layer_is_not_flagged():
    # z None or <= 0 means it does not stack above content -> not occluding.
    assert classify_overlay(_cand(z=None)) is None
    assert classify_overlay(_cand(z=0)) is None


def test_min_coverage_threshold_is_the_boundary():
    assert classify_overlay(_cand(coverage=0.49)) is None
    assert classify_overlay(_cand(coverage=0.50)) is not None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 -m pytest scripts/test_consent.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_consent'` (or `ImportError`).

- [ ] **Step 3: Write minimal implementation (with stubs for the next two tasks)**

Create `scripts/_consent.py` — implement `classify_overlay` now; add `overlay_dismissed` and `detect_and_dismiss` as `NotImplementedError` stubs so `test_consent.py`'s top-level import resolves (Tasks 2-3 fill them in):

```python
#!/usr/bin/env python3
"""_consent — pure core for G6 occluding-overlay (consent-class) handling.

A page's load-time occluding overlay (cookie/consent modal + backdrop, splash,
drawer) is a web_states State; dismissing it is a Transition. Detection is
CONTENT-BLIND geometry: position:fixed + viewport coverage + a positive z-index.
We never read text/class/id, and we never click a button (a blind click takes an
unknown real action — accept-tracking / nav-away — violating the honest-ceiling
principle). The only dismiss is an Escape keydown (content-blind, non-committal).

Detection errs toward UNDER-detect (documented, mirrors _states.diff_skeletons):
missing an overlay degrades to current behavior (the page behind is captured
regardless — §C7), whereas over-detect would mislabel a sticky-nav/hero/splash as
an un-cleared consent State. classify_overlay is the single policy gate; the JS
scan in web_states is a broad pre-filter, this is the decision."""
from __future__ import annotations

_OCCLUDING_POSITIONS = {"fixed"}


def classify_overlay(rec, *, min_coverage=0.5):
    """Map one scanned candidate record to an occluding_overlay State dict or None.

    rec keys (from web_states._OVERLAY_JS): position (computed CSS position string),
    z (int stacking, or None), coverage (clamped visible-fraction of the viewport,
    0..1), role (ARIA role or None), bbox ({x,y,w,h} ints). An element qualifies as
    an OCCLUDING overlay iff it is position:fixed AND covers >= min_coverage of the
    viewport AND has a positive z-index (establishes a layer above content)."""
    if rec.get("position") not in _OCCLUDING_POSITIONS:
        return None
    cov = rec.get("coverage") or 0.0
    if cov < min_coverage:
        return None
    z = rec.get("z")
    if z is None or z <= 0:
        return None
    return {"kind": "occluding_overlay", "coverage": cov, "z": z,
            "role": rec.get("role"), "bbox": rec.get("bbox")}


def overlay_dismissed(before, after_overlays, *, radius=24.0):
    raise NotImplementedError  # Task 2


def detect_and_dismiss(scan, dismiss, sleep, *, settle_ms=0.3, min_coverage=0.5):
    raise NotImplementedError  # Task 3
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest scripts/test_consent.py -q`
Expected: PASS (6 passed). The top-level import resolves (stubs exist); only the 6 `classify_overlay` tests exist at this point and they pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/_consent.py scripts/test_consent.py
git commit -m "feat(consent): add content-blind occluding-overlay classifier (G6 core)"
```

---

### Task 2: Pure core — `overlay_dismissed` (presence test)

**Files:**
- Modify: `scripts/_consent.py`
- Test: `scripts/test_consent.py`

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test_consent.py`:

```python
def test_overlay_gone_after_rescan_is_cleared():
    before = classify_overlay(_cand())
    # post-dismiss re-scan finds no occluding overlay
    assert overlay_dismissed(before, []) is True


def test_overlay_still_present_is_not_cleared():
    before = classify_overlay(_cand())
    after = [classify_overlay(_cand())]  # same full-bleed overlay still there
    assert overlay_dismissed(before, after) is False


def test_match_is_by_top_left_corner_within_radius():
    # A DIFFERENT occluding overlay at a far corner is not the same overlay, so the
    # original counts as cleared (corner match within radius=24 is the identity rule).
    before = classify_overlay(_cand())
    far = classify_overlay(_cand(bbox={"x": 600, "y": 400, "w": 680, "h": 400}))
    assert overlay_dismissed(before, [far]) is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest scripts/test_consent.py -q`
Expected: the 3 new tests FAIL — `NotImplementedError` from the `overlay_dismissed` stub; the 6 `classify_overlay` tests still pass.

- [ ] **Step 3: Write minimal implementation**

Replace the `overlay_dismissed` stub in `scripts/_consent.py`:

```python
def overlay_dismissed(before, after_overlays, *, radius=24.0):
    """Presence test (the INVERSE of G4's appeared-diff): given the overlay recorded
    pre-dismiss and the classify_overlay results re-scanned post-dismiss (Nones
    filtered out), the overlay is CLEARED iff no post-dismiss overlay sits at the
    same top-left corner (within radius px on both axes). We check the recorded
    overlay is GONE — we do NOT diff for newly-appeared nodes. radius mirrors
    _states.diff_skeletons (24.0)."""
    bb = before["bbox"]
    for o in after_overlays:
        ob = o["bbox"]
        if abs(ob["x"] - bb["x"]) <= radius and abs(ob["y"] - bb["y"]) <= radius:
            return False
    return True
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest scripts/test_consent.py -q`
Expected: PASS (9 passed — 6 classify + 3 dismissed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_consent.py scripts/test_consent.py
git commit -m "feat(consent): add overlay-dismissed presence test (G6 core)"
```

---

### Task 3: Pure core — `detect_and_dismiss` (I/O-injected orchestrator)

**Files:**
- Modify: `scripts/_consent.py`
- Test: `scripts/test_consent.py`

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test_consent.py`:

```python
def _scanner(*rounds):
    """Return a scan() that yields the next round's candidate list on each call."""
    seq = list(rounds)
    calls = {"n": 0}

    def scan():
        i = min(calls["n"], len(seq) - 1)
        calls["n"] += 1
        return seq[i]
    return scan


def test_no_overlay_returns_none():
    fired = {"dismiss": 0, "sleep": 0}
    out = detect_and_dismiss(
        _scanner([]),
        lambda: fired.__setitem__("dismiss", fired["dismiss"] + 1),
        lambda s: fired.__setitem__("sleep", fired["sleep"] + 1),
    )
    assert out is None
    assert fired["dismiss"] == 0  # no overlay -> no dismiss attempted


def test_escape_clears_overlay_records_cleared_true():
    # round 1: overlay present; round 2 (post-Escape): gone
    out = detect_and_dismiss(
        _scanner([_cand()], []),
        lambda: None, lambda s: None,
    )
    assert out["kind"] == "occluding_overlay"
    assert out["dismiss"] == "escape"
    assert out["cleared"] is True


def test_escape_ignored_records_cleared_false():
    # both rounds: the same overlay is still there (an Escape-ignoring wall)
    out = detect_and_dismiss(
        _scanner([_cand()], [_cand()]),
        lambda: None, lambda s: None,
    )
    assert out["dismiss"] == "escape"
    assert out["cleared"] is False


def test_dismiss_is_attempted_exactly_once_when_overlay_present():
    fired = {"dismiss": 0}
    detect_and_dismiss(
        _scanner([_cand()], []),
        lambda: fired.__setitem__("dismiss", fired["dismiss"] + 1),
        lambda s: None,
    )
    assert fired["dismiss"] == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest scripts/test_consent.py -q`
Expected: the 4 new tests FAIL — `NotImplementedError` from the `detect_and_dismiss` stub; the 9 prior tests still pass.

- [ ] **Step 3: Write minimal implementation**

Replace the `detect_and_dismiss` stub in `scripts/_consent.py`:

```python
def detect_and_dismiss(scan, dismiss, sleep, *, settle_ms=0.3, min_coverage=0.5):
    """Orchestrate G6 with injected I/O (the unit-testable seam, mirroring
    _settle.adaptive_settle). scan() -> raw candidate records (web_states._OVERLAY_JS);
    dismiss() -> fire the content-blind Escape gesture; sleep(seconds) -> wait for it
    to settle. Returns the consent State dict, or None when no occluding overlay is
    detected (the common case — see §C7). The State is content-free: geometry + z +
    role + the dismiss method + the cleared outcome.

    Only ONE overlay is recorded — the first detected (a backdrop covers the
    viewport, so the first qualifying full-bleed layer is the occluder). We attempt
    exactly one Escape; we never click (a blind click takes an unknown real action)."""
    overlay = _first_overlay(scan(), min_coverage)
    if overlay is None:
        return None
    dismiss()
    sleep(settle_ms)
    after = [o for o in (classify_overlay(r, min_coverage=min_coverage)
                         for r in (scan() or [])) if o]
    return {**overlay, "dismiss": "escape",
            "cleared": overlay_dismissed(overlay, after)}


def _first_overlay(cands, min_coverage):
    for r in (cands or []):
        o = classify_overlay(r, min_coverage=min_coverage)
        if o is not None:
            return o
    return None
```

- [ ] **Step 4: Run the FULL consent suite to verify all pass**

Run: `python3 -m pytest scripts/test_consent.py -q`
Expected: PASS (13 passed — 6 from Task 1, 3 from Task 2, 4 from Task 3).

- [ ] **Step 5: Commit**

```bash
git add scripts/_consent.py scripts/test_consent.py
git commit -m "feat(consent): add Escape-dismiss orchestrator with cleared outcome (G6 core)"
```

---

### Task 4: Wire G6 into `web_states` (scan + dismiss + record)

**Files:**
- Modify: `scripts/web_states.py` (imports near line 25; scan JS after `_AFFORD_JS`/`_CLICK_JS`; call in `main()` after the REST snapshot ~line 78; `out_obj` ~line 111)

- [ ] **Step 1: Add the import**

In `scripts/web_states.py`, after the existing `from _states import classify_trigger, diff_skeletons` line, add:

```python
from _consent import detect_and_dismiss
```

- [ ] **Step 2: Add the content-blind scan + dismiss JS**

After the `_CLICK_JS` definition (around line 60), add:

```python
# G6: content-blind occluding-overlay (consent-class) scan. Returns ONLY geometry +
# stacking + position for positioned, viewport-covering elements — never text/class/
# id. coverage = visible fraction of the viewport (rect clamped to the viewport).
# A broad pre-filter (fixed/sticky/absolute, coverage >= 0.3); _consent.classify_overlay
# is the policy gate that narrows to the occluding case (fixed + >=0.5 + z>0).
_OVERLAY_JS = r"""
(() => {
  const vw = innerWidth, vh = innerHeight, va = vw * vh;
  const out = [];
  for (const el of document.querySelectorAll('*')) {
    const cs = getComputedStyle(el);
    if (cs.position !== 'fixed' && cs.position !== 'sticky' && cs.position !== 'absolute') continue;
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    const x0 = Math.max(0, r.left), y0 = Math.max(0, r.top);
    const x1 = Math.min(vw, r.right), y1 = Math.min(vh, r.bottom);
    const w = Math.max(0, x1 - x0), h = Math.max(0, y1 - y0);
    const coverage = va > 0 ? (w * h) / va : 0;
    if (coverage < 0.3) continue;
    const z = parseInt(cs.zIndex, 10);
    out.push({position: cs.position,
              z: Number.isFinite(z) ? z : null,
              coverage: Math.round(coverage * 1000) / 1000,
              role: el.getAttribute('role'),
              bbox: {x: Math.round(r.left), y: Math.round(r.top),
                     w: Math.round(r.width), h: Math.round(r.height)}});
  }
  return out;
})()
"""

# G6 dismiss: the one content-blind, non-committal gesture. A synthetic Escape
# keydown/keyup on document. Never a button click (a blind click takes an unknown
# real action — accept-tracking / nav-away — violating the honest-ceiling principle).
_ESCAPE_JS = ("(() => { ['keydown','keyup'].forEach(t => document.dispatchEvent("
              "new KeyboardEvent(t, {key:'Escape', code:'Escape', keyCode:27, "
              "which:27, bubbles:true, cancelable:true}))); return true; })()")
```

- [ ] **Step 3: Call `detect_and_dismiss` after the REST snapshot**

In `main()`, immediately after the existing lines:

```python
        navigate(ev, engine, args.url)
        rest, _, _ = _snapshot_skeleton(ev, args.url)
        base_nodes = len(rest["nodes"])
```

add:

```python
        # G6: record the load-time occluding overlay (consent-class) as a State and
        # attempt one content-blind Escape dismiss. None when no overlay is detected
        # (the common case — §C7: overlays cover the DOM, they don't remove it).
        consent = detect_and_dismiss(lambda: ev.ev(_OVERLAY_JS),
                                     lambda: ev.ev(_ESCAPE_JS), time.sleep)
```

- [ ] **Step 4: Add `consent` to the emitted object**

Change the `out_obj` assignment (around line 111) from:

```python
        out_obj = {"schema": "probe-states/1", "url": args.url,
                   "base_nodes": base_nodes,
                   "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                   "states": states}
```

to:

```python
        out_obj = {"schema": "probe-states/1", "url": args.url,
                   "base_nodes": base_nodes, "consent": consent,
                   "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                   "states": states}
```

And in the `if args.out:` summary emit (around line 117), add a `consent` field so the CLI summary reflects it. Change:

```python
            emit_json({"ok": True, "out": args.out,
                       "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                       "states": len(states),
                       "appeared_total": sum(s["n_appeared"] for s in states)})
```

to:

```python
            emit_json({"ok": True, "out": args.out, "consent": consent,
                       "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                       "states": len(states),
                       "appeared_total": sum(s["n_appeared"] for s in states)})
```

- [ ] **Step 5: Verify the full unit suite still passes (no regressions)**

Run: `python3 -m pytest scripts/ -q`
Expected: PASS — the prior total (226) + the new `test_consent.py` (13) = **239 passed**. (`web_states.py` has no browser-dependent unit test; the change is import + JS strings + one call + one dict key, all exercised by the host gate in Task 5.)

- [ ] **Step 6: Commit**

```bash
git add scripts/web_states.py
git commit -m "feat(consent): wire content-blind overlay detection + Escape dismiss into web_states"
```

---

### Task 5: Host gate — both cases (the honesty pin)

**Files:**
- Create: `fixtures/consent/run_consent.py`

This gate is the G6 analog of P3-G1's `test_shell_trap_is_the_documented_ceiling`: it MUST exercise BOTH the Escape-dismissable overlay (`cleared: true`) AND the Escape-ignoring overlay (`cleared: false`). A gate that only tests the dismissable case fakes coverage. Browser-level behavior (synthetic Escape dispatch, computed-style coverage) is not unit-testable — this gate is the proof.

- [ ] **Step 1: Write the host gate**

Create `fixtures/consent/run_consent.py`:

```python
#!/usr/bin/env python3
"""Host gate: G6 occluding-overlay detection + content-blind Escape dismiss, BOTH cases.

Deterministic, offline. Serves two synthetic pages over 127.0.0.1, each with a
full-bleed position:fixed high-z overlay on a normal page behind it:
  /dismissable — the overlay removes itself on an Escape keydown  -> expect cleared:true
  /sticky      — the overlay ignores Escape (no listener)         -> expect cleared:false
Runs web_states against each (CDP, host Chrome) and asserts the `consent` State.

Why both: Escape clears few real consent walls; the honest output for those is
cleared:false. A gate that only tested /dismissable would fake coverage. This pins
the honest-ceiling direction (mirrors fixtures/settle/run_settle.py's pattern and
P3-G1's shell-trap unit pin)."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB_STATES = ROOT / "scripts" / "web_states.py"

# A normal page (>=120 boxes so the page-behind is real), plus a full-bleed
# position:fixed z:99999 overlay. The DISMISSABLE variant wires an Escape handler
# that removes the overlay; the STICKY variant has no handler.
_PAGE = """<!doctype html><meta charset=utf-8><title>g6</title>
<style>#ov{{position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.6)}}
.box{{height:8px}}</style>
<body>
{boxes}
<div id=ov></div>
<script>{script}</script>
</body>"""

_BOXES = "".join("<p class=box>%d</p>" % i for i in range(150))
_DISMISS_SCRIPT = ("document.addEventListener('keydown', e => {"
                   " if (e.key === 'Escape') { const o = document.getElementById('ov');"
                   " if (o) o.remove(); } });")
_STICKY_SCRIPT = "/* no Escape handler: this overlay ignores Escape */"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        script = _DISMISS_SCRIPT if self.path.startswith("/dismissable") else _STICKY_SCRIPT
        body = _PAGE.format(boxes=_BOXES, script=script).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    """Run web_states against url, return the parsed states.json object."""
    out = ROOT / "fixtures" / "consent" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    ok = True

    dis = _run(base + "/dismissable")
    if not dis:
        ok = False
    else:
        c = dis.get("consent")
        print("dismissable consent:", json.dumps(c))
        if not c or c.get("kind") != "occluding_overlay":
            print("GATE FAIL: dismissable — no occluding_overlay detected"); ok = False
        elif c.get("coverage", 0) < 0.5 or (c.get("z") or 0) <= 0:
            print("GATE FAIL: dismissable — overlay geometry below threshold"); ok = False
        elif c.get("cleared") is not True:
            print("GATE FAIL: dismissable — Escape did not clear (cleared != true)"); ok = False

    stk = _run(base + "/sticky")
    if not stk:
        ok = False
    else:
        c = stk.get("consent")
        print("sticky consent:", json.dumps(c))
        if not c or c.get("kind") != "occluding_overlay":
            print("GATE FAIL: sticky — no occluding_overlay detected"); ok = False
        elif c.get("cleared") is not False:
            print("GATE FAIL: sticky — overlay should NOT clear (cleared != false)"); ok = False

    srv.shutdown()
    if ok:
        print("GATE PASS: occluding overlay detected both ways; Escape cleared the "
              "dismissable one (cleared:true) and not the sticky one (cleared:false).")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Ensure host Chrome is running with a CDP endpoint**

`web_states` needs a CDP transport (host Chrome via `--cdp-port`, default discovered by `_web.chrome_running()` / `cdp_target()`). If no host Chrome is up, launch it the way the other gates do (see `fixtures/settle/run_navrace.py:60-62` — `chrome_launch(); time.sleep(1.0)`), or rely on an already-running instance. The sandbox CANNOT reach host Chrome — this gate runs on host Bash.

- [ ] **Step 3: Run the gate (host Bash, sandbox disabled)**

Run (on the host, NOT the ctx sandbox):
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/consent/run_consent.py`
Expected: STDOUT ends with `GATE PASS: ...`; exit code 0. The two `consent:` lines show `cleared: true` for `/dismissable` and `cleared: false` for `/sticky`, both with `kind: "occluding_overlay"`.

If it fails: read the printed `consent` JSON. Common causes — synthetic `KeyboardEvent` not honored (try dispatching on `document.body` or add `keyup`); overlay coverage rounding just under 0.5 (the fixture's `inset:0` overlay is coverage ~1.0, so this should not happen); Chrome not reachable on CDP (Step 2).

- [ ] **Step 4: Clean up the gate's scratch output**

Run: `rm -f /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/fixtures/consent/_out.json`
(The gate writes `_out.json` as scratch; do not commit it. Add it to `.gitignore` if the repo doesn't already ignore `fixtures/**/_out.json` / `out/`.)

- [ ] **Step 5: Commit**

```bash
git add fixtures/consent/run_consent.py
git commit -m "test(consent): host gate for overlay detection + Escape dismiss, both cases"
```

---

### Task 6: Documentation — results section + glossary line

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (append `§C9-R-P3-G6`; repoint the ladder pointer at the end of `§C9-R-P3`, line ~558)
- Modify: `CONTEXT.md` (one glossary line)

- [ ] **Step 1: Append the results section to the gap doc**

At the END of `docs/plans/probe-runner-engine-capture-gaps.md`, append:

```markdown

---

## §C9-R-P3-G6 — Results: G6 occluding-overlay (consent) State LANDED (2026-05-30)

G6 is implemented + verified (plan: `docs/plans/p3-g6-consent-state.md`; full unit suite green incl. `test_consent.py`; host gate `fixtures/consent/run_consent.py` green BOTH cases). Per the decided design, a consent overlay is a `web_states` State and dismiss is a Transition reusing the G4 machinery — NOT a `navigate()` concern.

**What it does.** After the REST snapshot, `web_states` scans for a load-time occluding overlay (content-blind: `position:fixed` + viewport coverage ≥ 0.5 + z-index > 0 — never text/class/id), records it as a content-free State (`kind:"occluding_overlay"`, `coverage`, `z`, `role`, `bbox`), fires one content-blind Escape keydown (the Transition), re-scans, and records `cleared: true|false`. Emitted as an additive `consent` key on `states.json` (schema stays `probe-states/1`); `null` when no occluding overlay is detected (the common case).

**Why it's small (§C7 is load-bearing).** §C7 proved overlays cover the DOM but do not remove it — the page behind is captured regardless. G6 is therefore a content-free RECORD of the occluding layer + an honest dismiss outcome, not an acquisition fix. The "defensive nicety" framing from the gap list holds.

**Honest ceiling (the both-cases gate pins it).** A blind button click is refused on principle (it takes an unknown real action — accept-tracking / nav-away). Escape clears only overlays that honor it; cookie WALLS that require reading "Accept" stay honestly `cleared: false`. The host gate exercises BOTH an Escape-dismissable overlay (`cleared:true`) and an Escape-ignoring one (`cleared:false`) — a gate testing only the dismissable case would fake coverage (the analog of P3-G1's `test_shell_trap_is_the_documented_ceiling`).

**Detection bias = UNDER-detect (documented).** `classify_overlay` requires `fixed` (not `absolute`/`sticky`) + coverage ≥ 0.5 + z > 0. Missing an overlay degrades to current behavior (page-behind still captured); over-detect would mislabel a sticky-nav / hero / splash as an un-cleared consent State. Same safe direction as G4's `diff_skeletons` under-count. Mechanism-honest naming: the data says `occluding_overlay` (it cannot prove "consent" content-blind), echoing P2's `iframe_uncaptured` and P3-G1's `settle`.

**Firewall:** `consent` is geometry (ints) + a position/role enum + the constants `dismiss:"escape"` / `cleared:bool` — content-free by construction; `audit_bundle` scans `states.json` as before, no new surface.

**§C9 ladder status:** P0 (scroll-motion), P1 (G10+G4), P2 (G5/G9/G11), P3-G1 (settle), **P3-G6 (consent) all landed.** The defensive P3 rung is complete. Remaining roadmap (not started): later acquisition gaps as they surface, full per-state component capture, iOS/Android/Flutter native.
```

- [ ] **Step 2: Repoint the live ladder pointer**

In `docs/plans/probe-runner-engine-capture-gaps.md`, find the line at the end of `§C9-R-P3` (~line 558) that begins `**Next on the §C9 ladder:** **G6 consent-dismiss** — decided design ...`. Replace that whole line with:

```markdown
**Next on the §C9 ladder:** G6 consent-dismiss LANDED — see §C9-R-P3-G6 (consent overlay = `web_states` `occluding_overlay` State; content-blind Escape dismiss Transition; honest `cleared` outcome). The defensive P3 rung (G1 settle + G6 consent) is complete; the live pointer is at the end of §C9-R-P3-G6.
```

- [ ] **Step 3: Add the glossary line to CONTEXT.md**

In `CONTEXT.md`, under the **State** definition (the entry that begins `**State**:`), append a sentence to its body:

```markdown
A page's load-time **occluding overlay** (a `position:fixed`, viewport-covering, top-of-stack layer — the consent-class mechanism) is one such State; `web_states` records it content-free (`kind:"occluding_overlay"`) and attempts a content-blind Escape **Transition**, honestly recording whether it `cleared`. It never clicks a button blind (that would take an unknown real action — an **Honest ceiling**).
```

- [ ] **Step 4: Verify the docs render and the suite is still green**

Run: `python3 -m pytest scripts/ -q`
Expected: PASS (239 passed — docs don't affect tests; this confirms nothing was broken mid-edit).

- [ ] **Step 5: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md CONTEXT.md
git commit -m "docs(consent): record G6 results, repoint ladder pointer, add glossary line"
```

---

## Final review (after all tasks)

Dispatch a final code reviewer over the whole G6 arc (commits from Task 1 through Task 6), then verify:

- [ ] `python3 -m pytest scripts/ -q` → 239 passed, clean tree.
- [ ] `fixtures/consent/run_consent.py` → GATE PASS (both `cleared:true` and `cleared:false` observed). Re-run on host if any doubt.
- [ ] `git log --oneline origin/master..HEAD` shows the 6 G6 commits; nothing pushed (the standing "do NOT push" constraint).
- [ ] Grep the diff for any content leak (the consent State must carry no text/url/class/id — only geometry + role + the two constants). `audit_bundle` already enforces this, but eyeball it.

## Self-review notes (author, pre-handoff)

- **Spec coverage:** decided design (overlay = State, dismiss = Transition, content-blind, not navigate()) → Tasks 1-4. Both-cases honesty pin → Task 5. Mechanism-honest naming + under-detect bias + §C7 framing → documented in code + Task 6.
- **Diff direction:** `overlay_dismissed` is a forward presence test, NOT `diff_skeletons` run backwards (advisor #4) — explicit in Task 2.
- **No "dismiss-first → cleaner sweep" claim** (advisor #5: `el.click()` already bypasses pointer-event occlusion, so that rationale is a false premise) — the consent step is placed before the affordance sweep only because the overlay is a load-time state; no reachability benefit is claimed.
- **Type consistency:** `classify_overlay` returns `{kind,coverage,z,role,bbox}`; `detect_and_dismiss` spreads it and adds `{dismiss,cleared}`; `overlay_dismissed(before, after_overlays)` consumes the same shape. `_OVERLAY_JS` record keys (`position,z,coverage,role,bbox`) match `classify_overlay`'s reads.
- **YAGNI:** no vendor selectors, no accept-text matching, no button click, no `bundle_writer --consent` CLI (the `consent` key rides on `states.json`, already bundle-able via `assemble(states=...)`).
```
