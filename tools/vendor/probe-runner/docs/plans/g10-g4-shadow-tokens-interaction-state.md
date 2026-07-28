# G10 shadow-DOM tokens + G4 interaction-state capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the two currently-invisible classes of design data the §C9 ladder ranks next — design tokens that live inside open Web-Component shadow roots (**G10**), and the structure that only appears after a non-URL interaction like opening a menu/disclosure/dialog (**G4**).

**Architecture:** G10 is a one-function change: `web_tokens`' single in-page collection pass (`_COLLECT_JS`) walks only the light DOM (`document.querySelectorAll('*')`), so tokens scoped inside `el.shadowRoot` are missed; make the walk recurse into open shadow roots. G4 adds a new verb `web_states` that navigates once, snapshots the REST skeleton, drives each discovered interaction affordance (click), re-snapshots, and diffs to record the nodes that **appeared** — emitting a content-free `states.json`. The skeleton re-snapshot reuses `web_skeleton` via a small extracted `_snapshot_skeleton` seam (capture-without-navigate, so the triggered state survives). A pure core `_states.py` (`classify_trigger`, `diff_skeletons`) holds all the testable logic; `bundle_writer` gains an optional `states.json` artifact that the existing firewall audit already scans.

**Tech Stack:** Python 3 (stdlib + the existing `_web_eval`/`_common`/`web_skeleton` modules; pytest), Chrome DevTools Protocol (`DOMSnapshot`, `Runtime.evaluate`). Canonical repo only: `~/Developer/artificial_intelligence/skills/probe-runner` (call it `$PR`); scripts dir `$PR/scripts` (call it `$SCR`). Run pytest from `$SCR` with `python3 -m pytest`.

**Source of truth (read before starting):**
- `docs/plans/probe-runner-engine-capture-gaps.md` §C9 (authoritative fix priority; this plan = its "P1"), §C6b (G10 shoelace measurement: light=455 vs deep=638, 183 elements hidden in shadow; `web_skeleton` pierces open roots, `web_tokens` does not), §C8 (cross-origin iframe / closed-root = hard boundary by analogy).
- `docs/plans/probe-runner-mode-c1-event-timelines.md` (precedent that **selectors are mechanism, not content** — the firewall scans selector-bearing artifacts and passes them).

---

## Execution notes (carry forward — non-negotiable)

- **CAVEMAN MODE full** in chat; **code/commits/security written normally**.
- **context-mode routing:** curl/wget/WebFetch BLOCKED → ctx tools. Bash for git/mkdir/rm/mv/ls/pytest-short only; large output → `ctx_execute`.
- **Two task classes** (marked per task):
  - **[PURE]** — pure-Python logic + pytest. Fully subagent-implementable (implement → spec review → quality review).
  - **[HOST]** — needs host Chrome CDP (`:9222`/`$PROBE_RUNNER_CHROME_CDP_PORT`). The ctx sandbox **cannot** reach host Chrome — these run on **host Bash with `dangerouslyDisableSandbox: true`**, and the **controller runs the live validation gate** (subagents stall on long CDP/background runs). Subagents still *write* the fixture/harness/verb files (plain file writes); the controller *executes* the host harness as the acceptance gate before the task is marked done. macOS has **no `timeout`** — use self-bounded Python wait loops (the harnesses already do via `subprocess` timeouts).
- **Every commit is GREEN.** Per-task spec+quality review runs against a passing suite — never commit a known-red test. Where TDD wants "see it fail first," that RED is *observed in a no-commit gate task*, then made green and committed in the following task. (This matches the repo's `run_anim.py` idiom: committed harnesses are green.)
- **Verify via exit codes / byte-sizes / git**, not narrative tool-result text.
- **Git:** commit only the files named in each step, staged **explicitly by path** (never `git add -A`/`.`). Commit messages **single line, NO author/Co-Authored-By trailer**. **Do NOT push** (commits stay local on `master` until the user asks).
- **IP firewall:** every emitted artifact is content-free by construction — node descriptors carry only `role`/`bbox`/`z`/`parent` and CSS-derived tokens; selectors are structural (`tag:nth-of-type(n)` paths), never text/`src`/`href`. The fixtures contain **no copyrighted content** (synthetic boxes/colors only).
- **Before substantive work and before declaring done: call advisor.** (Controller responsibility between tasks.)

---

## File structure (what this plan creates / modifies)

- **Modify** `$SCR/web_tokens.py` — recurse `_COLLECT_JS` into open shadow roots (G10). One function-shaped JS change; pure role/scale funcs untouched.
- **Modify** `$SCR/test_web_tokens.py` — fast regression guard that the collect JS descends shadow roots.
- **Create** `$PR/fixtures/shadow-dom/component.html` — deterministic Web Component whose shadow root carries tokens absent from the light DOM (G10 host gate).
- **Create** `$PR/fixtures/shadow-dom/run_tokens.py` — asserting host harness (serve fixture → `web_tokens` → assert shadow tokens captured).
- **Modify** `$SCR/web_skeleton.py` — extract `_snapshot_skeleton(ev, url, width=None)` (capture-without-navigate) out of `_capture_one`; `_capture_one` becomes navigate + `_snapshot_skeleton` (identical return tuple, existing behavior unchanged).
- **Create** `$SCR/_states.py` — pure G4 core: `classify_trigger(rec)` + `diff_skeletons(rest, after)`.
- **Create** `$SCR/test_states.py` — unit tests for the pure core.
- **Create** `$SCR/web_states.py` — live G4 verb: navigate → REST skeleton → affordance scan → click each → re-snapshot → diff → `states.json`.
- **Create** `$PR/fixtures/interaction-state/disclosure.html` — deterministic click-to-reveal panel (G4 host gate).
- **Create** `$PR/fixtures/interaction-state/run_states.py` — asserting host harness.
- **Modify** `$SCR/bundle_writer.py` — `assemble(..., states=None)` carries `states`; `write_bundle` writes `states.json` when present; firewall audit (already `rglob('*')`) covers it.
- **Modify** `$SCR/test_bundle_writer.py` — `states.json` round-trip + content-free audit pass; assert the no-states default is unchanged.

---

# Phase 1 — G10: web_tokens shadow-DOM walk

The smallest on-priority win. `web_skeleton` already pierces open shadow roots (DOMSnapshot does it natively); only `web_tokens` is blind because it samples computed styles via `document.querySelectorAll('*')`, which does not cross shadow boundaries.

---

### Task 1: G10 RED gate — fixture + host harness + fast guard (NO commit)  [HOST]

Write the deterministic gate that proves the gap, run it to confirm it is RED on current code, but **do not commit** (the assertions describe post-fix behavior; they go green and commit in Task 2). This is the "see it fail first" step.

**Files (written, not yet committed):**
- Create: `$PR/fixtures/shadow-dom/component.html`
- Create: `$PR/fixtures/shadow-dom/run_tokens.py`
- Modify: `$SCR/test_web_tokens.py` (append the fast guard)

- [ ] **Step 1: Write the fixture** — a Web Component whose shadow root carries a large-area background `#123456`, a `border-top-left-radius` of `13px`, and a `font-size` of `29px` — none present in the light DOM (whose only background is white). The host `x-card` is forced `display: block` so the block `.panel` inside the shadow root has non-zero area (an inline host would collapse it to area 0 → its bg would be dropped by the `area>0` sampling gate).

Create `$PR/fixtures/shadow-dom/component.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>shadow-dom token fixture</title>
<style>
  html, body { margin: 0; background: #ffffff; }
  x-card { display: block; }               /* host must be block so the shadow panel has area */
  /* light DOM carries NO #123456, NO radius 13, NO size 29 — the shadow root does */
</style>
</head>
<body>
  <x-card></x-card>
  <script>
    class XCard extends HTMLElement {
      constructor() {
        super();
        const root = this.attachShadow({ mode: 'open' });
        root.innerHTML = `
          <style>
            .panel {
              width: 100vw; height: 600px;
              background: rgb(18, 52, 86);           /* #123456 — shadow-only bg */
              border-top-left-radius: 13px;          /* shadow-only radius */
              color: rgb(200, 40, 90);
              font-family: 'ShadowSans';
              font-size: 29px;                       /* shadow-only type size */
              font-weight: 700;
            }
          </style>
          <div class="panel">x</div>`;
      }
    }
    customElements.define('x-card', XCard);
  </script>
</body>
</html>
```

- [ ] **Step 2: Write the asserting host harness** (mirrors `fixtures/scroll-motion/run_anim.py`: serve the fixture from disk, ensure host Chrome, run `web_tokens`, assert the shadow-only tokens reached `tokens.json`).

Create `$PR/fixtures/shadow-dom/run_tokens.py`:

```python
#!/usr/bin/env python3
"""Host harness: prove web_tokens captures design tokens that live INSIDE an
open Web-Component shadow root (G10). Serves a deterministic fixture whose
shadow root carries #123456 / radius 13 / size 29 — none in the light DOM — and
asserts they appear in tokens.json. MUST run on the host (host Chrome CDP at
:9222 / $PROBE_RUNNER_CHROME_CDP_PORT; the ctx sandbox cannot reach it).

  python3 fixtures/shadow-dom/run_tokens.py
"""
import http.server
import json
import os
import socket
import socketserver
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
OUT = "/tmp/shadow-dom"
os.makedirs(OUT, exist_ok=True)


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
    print("web_launch:", r.stdout.strip()[:160], r.stderr.strip()[:160])
    time.sleep(1.5)


def main():
    port = free_port()
    httpd = serve(HERE, port)
    print("serving", HERE, "on", port)
    ensure_chrome()
    outp = os.path.join(OUT, "tokens.json")
    if os.path.exists(outp):
        os.remove(outp)
    url = "http://127.0.0.1:%d/component.html" % port
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "web_tokens.py"),
             "--url", url, "--out", outp],
            capture_output=True, text=True, cwd=SCRIPTS, timeout=90)
    except subprocess.TimeoutExpired:
        print("FAIL — web_tokens timed out")
        httpd.server_close()
        return 1
    finally:
        httpd.server_close()
    print("exit:", r.returncode, "| stderr:", (r.stderr or "").strip()[-200:])
    if not os.path.exists(outp):
        print("FAIL — no tokens.json written")
        return 1
    with open(outp) as fh:
        tok = json.load(fh)
    palette = set((tok.get("palette") or {}).values())
    radii = tok.get("radii") or []
    sizes = tok.get("type_scale") or []
    print("palette:", sorted(v for v in palette if v), "| radii:", radii, "| type_scale:", sizes)
    ok = ("#123456" in palette) and (13 in radii) and (29 in sizes)
    if ok:
        print("PASS — shadow-root tokens captured (#123456 / radius 13 / size 29)")
        return 0
    print("FAIL — shadow tokens missing: ",
          {"#123456": "#123456" in palette, "radius13": 13 in radii, "size29": 29 in sizes})
    return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Append the fast regression guard** to `$SCR/test_web_tokens.py` (a browser-free check that the descent can't be silently removed later; the *behavioral* gate is the host harness):

```python
# ---- G10: collection pass descends open shadow roots ----

def test_collect_js_descends_shadow_roots():
    # The single in-page collection pass must recurse into el.shadowRoot, else
    # web-component design tokens (colors/type/radius scoped inside open shadow
    # roots) are missed. Guards against silent removal of the G10 descent.
    js = wt._COLLECT_JS
    assert "shadowRoot" in js, "collect JS no longer descends shadow roots (G10 regression)"
```

- [ ] **Step 4: Run both gates to confirm they are RED on current code**

Unit (subagent or controller): `cd $SCR && python3 -m pytest test_web_tokens.py::test_collect_js_descends_shadow_roots -q`
Expected: **FAIL** (`assert "shadowRoot" in js` — current `_COLLECT_JS` has no `shadowRoot`).

Host (**controller runs on host**, `dangerouslyDisableSandbox: true`): `cd $SCR && python3 ../fixtures/shadow-dom/run_tokens.py; echo EXIT=$?`
Expected: **`EXIT=1`** with `FAIL — shadow tokens missing` (the light-DOM-only walk never sees the shadow `.panel`). If `web_launch` shows no page target, `pkill -f 'Google Chrome'` then re-run (degraded probe-Chrome workaround).

- [ ] **Step 5: Do NOT commit.** Both gates are intentionally RED; they go green and commit in Task 2. Leave the three files in the working tree.

---

### Task 2: G10 implement the recursive shadow walk + GREEN commits  [PURE impl, HOST gate]

**Files:**
- Modify: `$SCR/web_tokens.py:162-192` (the `_COLLECT_JS` constant)
- Commit (now green): `web_tokens.py`, `test_web_tokens.py`, the two fixture files from Task 1.

- [ ] **Step 1: Replace `_COLLECT_JS`** — wrap the per-element body in a `visit(root)` function and recurse into `el.shadowRoot`. Replace the existing constant (`web_tokens.py` lines 162–192) verbatim with:

```python
# One in-page pass over every element's computed style. Emits the exact shapes
# the pure funcs consume: bg/fg/border as (css, weight) pairs (bg weighted by
# rendered area; text/border by count), font nodes as {"font": {...}} for
# build_scales, plus flat numeric gap/padding + radius lists and shadow strings.
# G10: the walk DESCENDS open shadow roots — web-component design tokens live
# inside them and querySelectorAll() on a parent root does not cross the shadow
# boundary. Closed roots (mode:'closed') expose no shadowRoot handle and stay
# unreachable (documented hard limit, like a cross-origin iframe — §C8).
_COLLECT_JS = r"""
(() => {
  const out = {bg: [], fg: [], border: [], fonts: [], spaces: [],
               radii: [], shadows: []};
  const visit = (root) => {
    for (const el of root.querySelectorAll('*')) {
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      const area = Math.max(0, r.width) * Math.max(0, r.height);
      if (area > 0) out.bg.push([cs.backgroundColor, area]);
      const leaf = el.children.length === 0 &&
                   (el.textContent || '').trim().length > 0;
      if (leaf) {
        out.fg.push([cs.color, 1]);
        out.fonts.push({font: {size: parseFloat(cs.fontSize),
                               weight: parseInt(cs.fontWeight, 10) || 400,
                               family: cs.fontFamily}});
      }
      if (parseFloat(cs.borderTopWidth) > 0) out.border.push([cs.borderTopColor, 1]);
      for (const p of [cs.gap, cs.paddingTop, cs.paddingRight,
                       cs.paddingBottom, cs.paddingLeft]) {
        const n = parseFloat(p);
        if (n > 0) out.spaces.push(n);
      }
      const rad = parseFloat(cs.borderTopLeftRadius);
      if (rad > 0) out.radii.push(rad);
      if (cs.boxShadow && cs.boxShadow !== 'none') out.shadows.push(cs.boxShadow);
      if (el.shadowRoot) visit(el.shadowRoot);   // G10: cross the open shadow boundary
    }
  };
  visit(document);
  out.shadows = Array.from(new Set(out.shadows)).slice(0, 8);
  return out;
})()
"""
```

- [ ] **Step 2: Run the full token unit suite — now GREEN**

Run: `cd $SCR && python3 -m pytest test_web_tokens.py -q`
Expected: all pass (the new `test_collect_js_descends_shadow_roots` is GREEN; existing tests untouched — the pure funcs were not changed).

- [ ] **Step 3: Run the host harness — now PASSES**  **[controller runs on host]**

Run (host Bash, `dangerouslyDisableSandbox: true`): `cd $SCR && python3 ../fixtures/shadow-dom/run_tokens.py; echo EXIT=$?`
Expected: **`EXIT=0`**, `PASS — shadow-root tokens captured (#123456 / radius 13 / size 29)`. This is the behavioral acceptance gate.

- [ ] **Step 4: Commit (two green commits — fix, then gate)**

```bash
git add scripts/web_tokens.py scripts/test_web_tokens.py
git commit -m "feat(web_tokens): descend open shadow roots in the token collection pass (G10)"
git add fixtures/shadow-dom/component.html fixtures/shadow-dom/run_tokens.py
git commit -m "test(web_tokens): shadow-DOM token fixture + host harness (G10 gate)"
```

---

# Phase 2 — G4: interaction-state capture (`web_states` + `states.json`)

Capture structure reachable only by a non-URL interaction (open menu / disclosure / dialog). Drive each affordance, re-snapshot the skeleton without re-navigating, and diff to record what appeared.

---

### Task 3: extract the capture-without-navigate seam  [PURE refactor]

**Files:**
- Modify: `$SCR/web_skeleton.py:335-389` (`_capture_one`)

`_capture_one` always navigates first, which would reset any triggered state. Split the post-navigate body into `_snapshot_skeleton(ev, url, width=None)` so G4 can re-snapshot the *current* page after a click. `_capture_one` keeps its exact `(skeleton, layout, page)` return.

> **Guard caveat (advisor):** the existing pure tests do NOT exercise `_capture_one`/`_snapshot_skeleton` (they test `parse_snapshot`/`to_skeleton`/etc.). Step 2 passing only proves the pure funcs didn't regress — it does **not** prove the seam itself is wired correctly. The seam is genuinely exercised end-to-end only by the G4 host gate (Task 7). Treat that as the real proof of this refactor.

- [ ] **Step 1: Replace `_capture_one`** (lines 335–389) with the extracted seam + a thin wrapper. The body below is the current `_capture_one` body verbatim, minus the leading `navigate(...)`, moved into `_snapshot_skeleton`:

```python
def _snapshot_skeleton(ev, url, width=None):
    """Force REST + capture ONE DOMSnapshot at the page's CURRENT state — NO
    navigate. Split out of _capture_one so callers that drive non-URL state
    (web_states / G4) can re-snapshot AFTER a trigger without reloading and
    losing that state. Returns (skeleton, layout, page); _REST_JS only scrolls to
    top (it does not close a click-opened menu/dialog)."""
    if width is not None and hasattr(ev, "sess"):
        ev.sess.send("Emulation.setDeviceMetricsOverride",
                     {"width": int(width), "height": 900,
                      "deviceScaleFactor": 1, "mobile": False})
        time.sleep(0.1)  # let the resize reflow before forcing REST
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

    # DOMSnapshot bounds are device px. Live path (width is None): divide by JS
    # devicePixelRatio. --viewports path (width set): JS dpr collapses to 1 under
    # the Emulation override, so measure the true backing scale via getLayoutMetrics.
    eff_dpr = _backing_scale(ev) if width is not None else (layout["dpr"] or 1.0)
    recs = parse_snapshot(snap, WANT_STYLES, dpr=eff_dpr)
    svg_set = set()
    parent_index = None
    for doc in snap["documents"]:
        svg_set |= svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, node_colors = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads this; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    return sk, layout, page


def _capture_one(ev, engine, url, width=None):
    """Navigate, force REST, capture one DOMSnapshot; return (skeleton, layout,
    page). The skeleton carries a top-level `_node_colors` sidecar (consumed by
    bundle_writer to resolve token_ref; ignored by the crate).

    `width` (multi-breakpoint capture): override the layout-viewport width via
    CDP Emulation before snapshotting, so bboxes reflect that breakpoint. CDP
    reverts the override when the inspector session closes, so the caller's
    open tab is left untouched. No-op on non-CDP transports."""
    navigate(ev, engine, url)
    return _snapshot_skeleton(ev, url, width=width)
```

- [ ] **Step 2: Run the existing skeleton + bundle tests as a regression guard**

Run: `cd $SCR && python3 -m pytest test_web_skeleton.py test_bundle_writer.py -q`
Expected: PASS (pure tests unchanged; `_capture_one`'s contract is unchanged). See the guard caveat above — this proves no regression, not seam correctness.

- [ ] **Step 3: Commit the seam**

```bash
git add scripts/web_skeleton.py
git commit -m "refactor(web_skeleton): extract _snapshot_skeleton (capture-without-navigate) for G4 state re-capture"
```

---

### Task 4: `classify_trigger` — pure affordance classifier  [PURE]

**Files:**
- Create: `$SCR/_states.py`
- Create: `$SCR/test_states.py`

- [ ] **Step 1: Write the failing tests** — create `$SCR/test_states.py`:

```python
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _states import classify_trigger


def test_aria_haspopup_is_menu_click():
    rec = {"tag": "BUTTON", "role": None, "ariaHaspopup": "true",
           "ariaExpanded": "false", "hasOpen": False, "selector": "html > body > button:nth-of-type(1)"}
    assert classify_trigger(rec) == {"kind": "menu", "action": "click"}


def test_details_summary_is_disclosure():
    assert classify_trigger({"tag": "SUMMARY", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": None, "hasOpen": False, "selector": "x"}) \
        == {"kind": "disclosure", "action": "click"}


def test_aria_expanded_false_is_disclosure():
    assert classify_trigger({"tag": "DIV", "role": "button", "ariaHaspopup": None,
                             "ariaExpanded": "false", "hasOpen": False, "selector": "x"}) \
        == {"kind": "disclosure", "action": "click"}


def test_already_expanded_is_skipped():
    # aria-expanded already true -> the state is open; nothing new to reveal.
    assert classify_trigger({"tag": "DIV", "role": "button", "ariaHaspopup": None,
                             "ariaExpanded": "true", "hasOpen": False, "selector": "x"}) is None


def test_plain_element_is_not_a_trigger():
    assert classify_trigger({"tag": "DIV", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": None, "hasOpen": False, "selector": "x"}) is None
```

- [ ] **Step 2: Run to verify failure**

Run: `cd $SCR && python3 -m pytest test_states.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named '_states'`.

- [ ] **Step 3: Write `_states.py` with `classify_trigger`** — create `$SCR/_states.py`:

```python
#!/usr/bin/env python3
"""_states — pure core for G4 interaction-state capture (no browser, no I/O).

`classify_trigger`: decide whether a scanned affordance record is a drivable
interaction trigger, and how. `diff_skeletons`: given a REST skeleton and a
post-trigger skeleton, return the nodes that APPEARED (content-free descriptors).
Both are deterministic and unit-tested; web_states.py wraps them with CDP I/O."""
from __future__ import annotations

_DISCLOSURE_TAGS = {"SUMMARY", "DETAILS"}


def classify_trigger(rec):
    """Map a scanned affordance record to {"kind", "action"} or None.

    rec keys (all from the in-page affordance scan): tag (UPPER), role,
    ariaHaspopup, ariaExpanded, hasOpen, selector. An element already in the
    expanded/open state (aria-expanded == "true") is skipped — its content is
    already visible at REST, so clicking would only CLOSE it."""
    tag = (rec.get("tag") or "").upper()
    haspopup = rec.get("ariaHaspopup")
    expanded = rec.get("ariaExpanded")

    if expanded == "true":
        return None
    if tag in _DISCLOSURE_TAGS:
        return {"kind": "disclosure", "action": "click"}
    if haspopup and haspopup != "false":
        return {"kind": "menu", "action": "click"}
    if expanded == "false":
        return {"kind": "disclosure", "action": "click"}
    return None
```

- [ ] **Step 4: Run to verify pass**

Run: `cd $SCR && python3 -m pytest test_states.py -q`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/_states.py scripts/test_states.py
git commit -m "feat(_states): classify_trigger — pure affordance classifier for G4 interaction triggers"
```

---

### Task 5: `diff_skeletons` — pure appeared-node diff  [PURE]

**Files:**
- Modify: `$SCR/_states.py`
- Modify: `$SCR/test_states.py`

- [ ] **Step 1: Write the failing tests** — append to `$SCR/test_states.py`:

```python
from _states import diff_skeletons


def _node(nid, role, x, y, w, h, z=0):
    return {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z}


def test_diff_flags_newly_appeared_nodes():
    rest = {"nodes": [_node(0, "box", 0, 0, 1280, 40)]}
    after = {"nodes": [
        _node(0, "box", 0, 0, 1280, 40),          # unchanged (matches rest)
        _node(1, "menuitem", 100, 200, 300, 60),  # NEW
        _node(2, "menuitem", 100, 270, 300, 60),  # NEW
        _node(3, "menuitem", 100, 340, 300, 60),  # NEW
    ]}
    d = diff_skeletons(rest, after)
    assert d["n_appeared"] == 3, d
    assert all(a["role"] == "menuitem" for a in d["appeared"])
    assert "bbox" in d["appeared"][0] and "z" in d["appeared"][0]


def test_diff_ignores_small_shifts():
    # a node that merely shifts a few px is the SAME node, not "appeared".
    rest = {"nodes": [_node(0, "box", 0, 0, 200, 50)]}
    after = {"nodes": [_node(0, "box", 3, 2, 200, 50)]}
    assert diff_skeletons(rest, after)["n_appeared"] == 0


def test_diff_accepts_bare_node_lists():
    rest = [_node(0, "box", 0, 0, 200, 50)]
    after = [_node(0, "box", 0, 0, 200, 50), _node(1, "box", 500, 500, 80, 80)]
    assert diff_skeletons(rest, after)["n_appeared"] == 1


def test_diff_role_change_at_same_spot_counts_as_appeared():
    # different role at the same geometry is a genuinely different node.
    rest = {"nodes": [_node(0, "box", 10, 10, 100, 100)]}
    after = {"nodes": [_node(0, "dialog", 10, 10, 100, 100)]}
    assert diff_skeletons(rest, after)["n_appeared"] == 1
```

- [ ] **Step 2: Run to verify failure**

Run: `cd $SCR && python3 -m pytest test_states.py -q`
Expected: FAIL (`ImportError: cannot import name 'diff_skeletons'`).

- [ ] **Step 3: Implement `diff_skeletons`** — append to `$SCR/_states.py`:

```python
def _nodes(sk):
    """Accept either a skeleton dict ({"nodes": [...]}) or a bare node list."""
    return sk.get("nodes", []) if isinstance(sk, dict) else (sk or [])


def _center(b):
    return (b["x"] + b["w"] / 2.0, b["y"] + b["h"] / 2.0)


def diff_skeletons(rest, after, radius=24.0):
    """Return {"appeared": [...], "n_appeared": N}: the after-trigger nodes with
    NO matching REST node. A match = same role AND center within `radius` px on
    both axes AND size within `radius` px on both dims (so a small reflow shift is
    the SAME node, not a new one). Appeared descriptors are content-free
    (role/bbox/z only) — the firewall-safe record of what the interaction revealed."""
    rest_nodes = _nodes(rest)
    appeared = []
    for a in _nodes(after):
        ab = a["bbox"]
        ac = _center(ab)
        matched = False
        for r in rest_nodes:
            if a.get("role") != r.get("role"):
                continue
            rb = r["bbox"]
            rc = _center(rb)
            if (abs(ac[0] - rc[0]) <= radius and abs(ac[1] - rc[1]) <= radius
                    and abs(ab["w"] - rb["w"]) <= radius
                    and abs(ab["h"] - rb["h"]) <= radius):
                matched = True
                break
        if not matched:
            appeared.append({"role": a.get("role"), "bbox": ab, "z": a.get("z", 0)})
    return {"appeared": appeared, "n_appeared": len(appeared)}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd $SCR && python3 -m pytest test_states.py -q`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/_states.py scripts/test_states.py
git commit -m "feat(_states): diff_skeletons — pure appeared-node diff for G4 state capture"
```

---

### Task 6: `web_states.py` — live G4 verb  [HOST impl; controller validates in Task 7]

**Files:**
- Create: `$SCR/web_states.py`

- [ ] **Step 1: Write the verb** — create `$SCR/web_states.py`:

```python
#!/usr/bin/env python3
"""web_states — drive non-URL interaction state (G4) and capture what appears.

Navigate once, snapshot the REST skeleton, scan the page for interaction
affordances (aria-haspopup / aria-expanded / <details>/<summary>), click each,
re-snapshot WITHOUT re-navigating (so the triggered state survives), and diff to
record the nodes that appeared. Emits a content-free states.json:

  {"schema": "probe-states/1", "url": ..., "base_nodes": N,
   "states": [{"trigger": {"selector","kind","action"},
               "n_appeared": M, "appeared": [{"role","bbox","z"}, ...]}, ...]}

Selectors are structural (tag:nth-of-type paths) — mechanism, not content. MUST
run on a CDP transport (host Chrome / --cdp-port); the ctx sandbox cannot reach
host Chrome."""
from __future__ import annotations
import argparse
import json
import time
from pathlib import Path

from _common import die, emit_json
from _web_eval import add_transport_args, navigate, resolve_web_eval
from web_skeleton import _snapshot_skeleton
from _states import classify_trigger, diff_skeletons

# In-page scan: collect ONLY affordance candidates (targeted selector keeps the
# payload small) with a structural, content-free CSS path for each. Closed shadow
# roots and cross-origin frames are out of reach (documented hard limits).
_AFFORD_JS = r"""
(() => {
  const path = (el) => {
    const parts = [];
    while (el && el.nodeType === 1) {
      const tag = el.tagName.toLowerCase();
      let n = 1, sib = el;
      while ((sib = sib.previousElementSibling)) {
        if (sib.tagName === el.tagName) n++;
      }
      parts.unshift(tag + ':nth-of-type(' + n + ')');
      el = el.parentElement;
    }
    return parts.join(' > ');
  };
  const sel = '[aria-haspopup],[aria-expanded],details,summary,[role=menu]';
  const out = [];
  for (const el of document.querySelectorAll(sel)) {
    out.push({tag: el.tagName,
              role: el.getAttribute('role'),
              ariaHaspopup: el.getAttribute('aria-haspopup'),
              ariaExpanded: el.getAttribute('aria-expanded'),
              hasOpen: el.hasAttribute('open'),
              selector: path(el)});
  }
  return out;
})()
"""

_CLICK_JS = ("(() => { const el = document.querySelector(%s);"
             " if (!el) return false; el.click(); return true; })()")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=None, help="write states.json here")
    p.add_argument("--max", type=int, default=8,
                   help="cap the number of triggers driven (default 8)")
    add_transport_args(p)  # supplies --url + transport/device flags
    args = p.parse_args()
    if not args.url:
        die("web_states needs --url (the page to drive interaction state on).")

    engine, ev, device = resolve_web_eval(args)
    try:
        if not hasattr(ev, "sess"):
            die("web_states needs a CDP transport (chrome host / --cdp-port).")
        navigate(ev, engine, args.url)
        rest, _, _ = _snapshot_skeleton(ev, args.url)

        cands = ev.ev(_AFFORD_JS) or []
        triggers = []
        for c in cands:
            t = classify_trigger(c)
            if t:
                triggers.append({"selector": c["selector"], **t})

        states = []
        for tr in triggers[:args.max]:
            opened = ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
            if not opened:
                continue
            time.sleep(0.3)  # let the reveal animate/lay out
            after, _, _ = _snapshot_skeleton(ev, args.url)
            d = diff_skeletons(rest, after)
            states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                           "appeared": d["appeared"]})
            # toggle back so each trigger is measured against the same REST base
            ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
            time.sleep(0.15)

        out_obj = {"schema": "probe-states/1", "url": args.url,
                   "base_nodes": len(rest["nodes"]), "states": states}
        if args.out:
            Path(args.out).write_text(json.dumps(out_obj, indent=2))
            emit_json({"ok": True, "out": args.out, "states": len(states),
                       "appeared_total": sum(s["n_appeared"] for s in states)})
        else:
            emit_json(out_obj)
    finally:
        ev.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Byte-level sanity (no browser)** — confirm the module imports and argparse builds (catches syntax/import errors before the host run):

Run: `cd $SCR && python3 -c "import web_states; print('import ok')" && python3 web_states.py --help >/dev/null && echo HELP_OK`
Expected: `import ok` then `HELP_OK`.

- [ ] **Step 3: Commit the verb**

```bash
git add scripts/web_states.py
git commit -m "feat(web_states): live G4 verb — drive interaction affordances, diff appeared nodes to states.json"
```

---

### Task 7: G4 host fixture + asserting harness  [HOST]

**Files:**
- Create: `$PR/fixtures/interaction-state/disclosure.html`
- Create: `$PR/fixtures/interaction-state/run_states.py`

This gate is GREEN at commit time because the verb (Task 6) is already implemented — the harness exercises and confirms it.

- [ ] **Step 1: Write the fixture** — a button (`aria-haspopup`/`aria-expanded`) that on click reveals a `display:none` panel of three structural boxes (content-free). At REST the boxes have zero area (dropped by `web_skeleton`'s area>0 filter); after click they appear.

Create `$PR/fixtures/interaction-state/disclosure.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>interaction-state fixture</title>
<style>
  html, body { margin: 0; background: #ffffff; font-family: sans-serif; }
  #opener { width: 120px; height: 40px; }
  #panel { display: none; }
  #panel.open { display: block; }
  .item { width: 300px; height: 60px; background: #eeeeee; margin: 8px; }
</style>
</head>
<body>
  <button id="opener" aria-haspopup="true" aria-expanded="false">menu</button>
  <div id="panel" role="menu">
    <div class="item"></div>
    <div class="item"></div>
    <div class="item"></div>
  </div>
  <script>
    const b = document.getElementById('opener');
    const p = document.getElementById('panel');
    b.addEventListener('click', () => {
      const open = p.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  </script>
</body>
</html>
```

- [ ] **Step 2: Write the asserting host harness** — create `$PR/fixtures/interaction-state/run_states.py`:

```python
#!/usr/bin/env python3
"""Host harness: prove web_states recovers structure revealed only by a non-URL
interaction (G4). Serves a click-to-reveal fixture (3 boxes hidden at REST) and
asserts web_states reports a state whose n_appeared >= 3. MUST run on the host
(host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT).

  python3 fixtures/interaction-state/run_states.py
"""
import http.server
import json
import os
import socket
import socketserver
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
OUT = "/tmp/interaction-state"
os.makedirs(OUT, exist_ok=True)


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
    print("web_launch:", r.stdout.strip()[:160], r.stderr.strip()[:160])
    time.sleep(1.5)


def main():
    port = free_port()
    httpd = serve(HERE, port)
    print("serving", HERE, "on", port)
    ensure_chrome()
    outp = os.path.join(OUT, "states.json")
    if os.path.exists(outp):
        os.remove(outp)
    url = "http://127.0.0.1:%d/disclosure.html" % port
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "web_states.py"),
             "--url", url, "--out", outp],
            capture_output=True, text=True, cwd=SCRIPTS, timeout=120)
    except subprocess.TimeoutExpired:
        print("FAIL — web_states timed out")
        httpd.server_close()
        return 1
    finally:
        httpd.server_close()
    print("exit:", r.returncode, "| stderr:", (r.stderr or "").strip()[-200:])
    if not os.path.exists(outp):
        print("FAIL — no states.json written")
        return 1
    with open(outp) as fh:
        st = json.load(fh)
    states = st.get("states", [])
    best = max((s.get("n_appeared", 0) for s in states), default=0)
    print("states:", len(states), "| max n_appeared:", best,
          "| triggers:", [s["trigger"]["kind"] for s in states])
    if states and best >= 3:
        print("PASS — interaction revealed >=3 nodes (G4)")
        return 0
    print("FAIL — no state revealed the hidden panel (expected n_appeared >= 3)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run the harness — expect PASS**  **[controller runs on host]**

Run (host Bash, `dangerouslyDisableSandbox: true`): `cd $SCR && python3 ../fixtures/interaction-state/run_states.py; echo EXIT=$?`
Expected: **`EXIT=0`**, `PASS — interaction revealed >=3 nodes (G4)`. If `web_launch` shows no page target, `pkill -f 'Google Chrome'` then re-run.

> If it fails because the selector path missed or the toggle reopened nothing: print `states.json` and inspect `trigger.selector`. The fixture's opener is the only `[aria-haspopup]`, so the scan must yield exactly one `menu` trigger with `n_appeared == 3`.

- [ ] **Step 4: Commit the fixture + harness**

```bash
git add fixtures/interaction-state/disclosure.html fixtures/interaction-state/run_states.py
git commit -m "test(web_states): interaction-state fixture + host harness (G4 GREEN gate)"
```

---

### Task 8: bundle `states.json` artifact + firewall round-trip  [PURE]

**Files:**
- Modify: `$SCR/bundle_writer.py:134-173` (`assemble` + `write_bundle`)
- Modify: `$SCR/test_bundle_writer.py`

Make `states.json` an optional bundle artifact. The firewall audit already `rglob('*')`-scans every file in the bundle, so a leaked string in `states.json` would be caught — this task adds it to the write path and proves the content-free round-trip. (Verified: `test_bundle_writer.py:177` asserts the default `assemble` returns exactly `{meta,skeleton,tokens,motion,manifest}`; the conditional `states` add below keeps that assertion green.)

- [ ] **Step 1: Write the failing tests** — append to `$SCR/test_bundle_writer.py`:

```python
# ---- G4: optional states.json artifact ----

def test_assemble_omits_states_key_by_default():
    import bundle_writer as bw
    skeleton = {"schema": "probe-skeleton/2", "url": "http://x", "nodes": [],
                "viewport": {"w": 1280, "h": 800, "dpr": 1}, "page": {"w": 1280, "h": 800}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    assert "states" not in bundle   # default unchanged: no states key


def test_write_bundle_emits_states_json_and_passes_audit(tmp_path):
    import json, bundle_writer as bw
    skeleton = {"schema": "probe-skeleton/2", "url": "http://x", "nodes": [],
                "viewport": {"w": 1280, "h": 800, "dpr": 1}, "page": {"w": 1280, "h": 800}}
    states = {"schema": "probe-states/1", "url": "http://x", "base_nodes": 0,
              "states": [{"trigger": {"selector": "html > body > button:nth-of-type(1)",
                                       "kind": "menu", "action": "click"},
                          "n_appeared": 2,
                          "appeared": [{"role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}, "z": 0},
                                       {"role": "box", "bbox": {"x": 0, "y": 20, "w": 10, "h": 10}, "z": 0}]}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, states=states)
    assert bundle["states"] == states
    bw.write_bundle(bundle, str(tmp_path))      # must NOT raise ContentLeak
    written = json.loads((tmp_path / "states.json").read_text())
    assert written["states"][0]["trigger"]["kind"] == "menu"
```

- [ ] **Step 2: Run to verify failure**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -q -k states`
Expected: FAIL (`assemble() got an unexpected keyword argument 'states'`).

- [ ] **Step 3: Add the `states` param to `assemble`** — change the signature and the returned dict in `bundle_writer.py`.

Replace the `assemble` signature line:
```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra):
```
with:
```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None):
```

Replace the `return { ... }` block (the dict literal at lines ~152–158) with:
```python
    bundle = {
        "meta": meta,
        "skeleton": skeleton,
        "tokens": tokens,
        "motion": motion,
        "manifest": manifest,
    }
    if states is not None:
        bundle["states"] = states   # G4 interaction-state artifact (optional)
    return bundle
```

- [ ] **Step 4: Write `states.json` in `write_bundle`** — in `write_bundle`, immediately BEFORE the `viol = cf.audit_bundle(root)` line, add:

```python
    if "states" in bundle:
        (root / "states.json").write_text(json.dumps(bundle["states"], indent=2))
```

- [ ] **Step 5: Run to verify pass**

Run: `cd $SCR && python3 -m pytest test_bundle_writer.py -q`
Expected: all pass (the two new `states` tests + every pre-existing bundle test — the default path is unchanged because `states` defaults to `None` and the key is omitted).

- [ ] **Step 6: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat(bundle_writer): optional states.json artifact (G4) — written when present, firewall-audited"
```

---

## Final acceptance (controller, after all tasks)

- [ ] **Full unit suite green:** `cd $SCR && python3 -m pytest -q` → all pass.
- [ ] **G10 host gate:** `python3 ../fixtures/shadow-dom/run_tokens.py` → `EXIT=0` PASS.
- [ ] **G4 host gate:** `python3 ../fixtures/interaction-state/run_states.py` → `EXIT=0` PASS.
- [ ] **Clean tree, no push:** `git status` clean; `git log --oneline` shows the new commits local on `master`.
- [ ] **Honesty record:** append a short results section to `docs/plans/probe-runner-engine-capture-gaps.md` §C9 noting G10 (open roots fixed; closed roots remain a hard limit) and G4 (explicit-affordance triggers landed via aria/details; hover-only and JS-custom triggers are a documented follow-up). Commit single-line.

---

## Self-review (run against §C9 / §C6b before execution)

**1. Spec coverage.**
- §C9 P1 = "G10 web_tokens shadow-walk + G4 interaction-state triggers." → G10 = Tasks 1–2 (RED gate, then recursive `shadowRoot` descent + green commits). G4 = Tasks 3–8 (capture seam, classifier, diff, verb, host gate, bundle artifact). ✔
- §C6b "skeleton already pierces, tokens do not" → only `web_tokens` is changed for G10; `web_skeleton` is untouched except the no-behavior-change `_snapshot_skeleton` extraction. ✔
- §C8 hard-boundary analogy → closed shadow roots / cross-origin frames are explicitly documented as unreachable in code comments and the final honesty note, not silently skipped. ✔
- Firewall: selectors-as-mechanism precedent honored (mode-c1); `states.json` goes through `audit_bundle`; appeared-node descriptors carry no content keys. ✔

**2. Placeholder scan.** No "TBD/handle edge cases/similar to Task N" — every code step is complete and verbatim, every command has an expected result. ✔

**3. Type consistency.** `_snapshot_skeleton` returns the same `(skeleton, layout, page)` tuple `_capture_one` always returned; `web_states` consumes it as `rest, _, _`. `classify_trigger` returns `{"kind","action"}|None`; `web_states` spreads it next to `selector` → `{"selector","kind","action"}`, the exact shape `states.json` and the bundle test assert. `diff_skeletons` returns `{"appeared","n_appeared"}` consumed identically by the verb and both harnesses. `assemble(..., states=None)` adds a trailing optional arg — every existing caller (incl. `main()`) is unaffected, and the `keys()==5` default assertion stays green. ✔

**4. Commit hygiene.** Every commit lands green (G10's RED is observed in Task 1's no-commit gate, made green in Task 2). Single-line messages, explicit path staging, no push. ✔
