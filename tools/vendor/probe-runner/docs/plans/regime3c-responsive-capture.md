# Regime-3c Responsive Multi-Viewport Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture, as an additive per-node `responsive` sidecar, the resolved-CSS reflow delta each element takes at narrower viewport widths vs a widest-width base — `@media` / `clamp()` / viewport-tracking `@container` restyle — joined by `backendNodeId`, content-free.

**Architecture:** Structural clone of Regime-3a/3b on the viewport-width axis. `web_skeleton --breakpoints` navigates ONCE at the widest width (base), then for each narrower width applies `Emulation.setDeviceMetricsOverride` with NO re-navigate, recaptures a DOMSnapshot over a curated `RESPONSIVE_PROPS` set, and diffs resolved styles vs base — reusing the `_theme.py` pure diff core UNCHANGED (`styles_by_backend`/`diff_theme`/`rekey_by_node_id`/`build_node_theme`). The join key is the stable `backendNodeId` (probe R2). Deltas are redacted by an alias of the theme redactor and threaded through `bundle_writer` exactly like `theme`/`pseudo_state`; `content_firewall.py` is UNCHANGED.

**Tech Stack:** Python 3, CDP (`Emulation.setDeviceMetricsOverride` / `DOMSnapshot.captureSnapshot`), pytest. Host CDP gate runs on host Bash (CDP unreachable from the ctx sandbox).

**Design spec:** `docs/plans/regime3c-responsive-capture-design.md` (probe facts R1–R7 in §1; the controller has already run and deleted that probe).

---

## File structure (what this plan creates / modifies)

- **Modify** `scripts/_style.py` — append `redact_responsive = redact_theme` alias (T1).
- **Modify** `scripts/test_style.py` — alias identity + redaction tests (T1).
- **Modify** `scripts/web_skeleton.py` — add `RESPONSIVE_PROPS` + `DEFAULT_BREAKPOINTS` constants; generalize `_snapshot_recs(ev, props=WANT_STYLES)`; add `capture_with_breakpoints`; add `--breakpoints` flag + its `elif` branch (T2, T5).
- **Modify** `scripts/test_web_skeleton.py` — `_snapshot_recs` generalization test, `RESPONSIVE_PROPS` shape test (T2); `capture_with_breakpoints` orchestration tests (T5).
- **Modify** `scripts/bundle_writer.py` — `apply_node_responsive`; `assemble(..., node_responsive=None)`; `main` pops `_node_responsive` (T3).
- **Modify** `scripts/test_bundle_writer.py` — `apply_node_responsive` round-trip + None-safe (T3).
- **Modify** `scripts/test_content_firewall.py` — prose canary into `responsive` (T4). `content_firewall.py` UNCHANGED.
- **Create** `fixtures/responsive/run_responsive.py` — host CDP gate (T6, controller-run).
- **Create** `fixtures/responsive/validate_realsite.py` — content-free real-site harness (after-task, controller-run).

**Commit discipline (standing constraints — non-negotiable):** single-line commit messages, NO trailers / NO `Co-Authored-By` / NO body. Stage files EXPLICITLY by path; NEVER `git add -A`/`git add .`. ONE commit per task; a review-driven fix gets its OWN commit. Do NOT push. `backendNodeId` / CDP `nodeId` NEVER on disk. Implementer subagents write gate/harness files + static-check only (`python3 -c "import ast; ast.parse(open(...).read())"`); the CONTROLLER runs the CDP gate (T6) and all after-tasks.

---

### Task 1: `redact_responsive` alias

**Files:**
- Modify: `scripts/_style.py` (after line 141, `redact_pseudo_state = redact_theme`)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_style.py`, extend the import on line 7 and add two tests after the `redact_pseudo_state` tests:

```python
from _style import redact_theme, redact_pseudo_state, redact_responsive  # noqa: E402
```

```python
def test_redact_responsive_is_redact_theme_alias():
    # Regime-3c responsive deltas share the {label:{prop:value}} delta shape exactly;
    # the redactor is the SAME function (alias, not a copy) so the two cannot drift.
    assert redact_responsive is redact_theme


def test_redact_responsive_keeps_layout_value_redacts_url():
    out = redact_responsive({"768": {"display": "block",
                                     "background-image": 'url("https://a/b.png")'}})
    assert out["768"]["display"] == "block"          # layout keyword kept verbatim
    assert out["768"]["background-image"] == 'url("<asset>")'   # external url redacted
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_responsive_is_redact_theme_alias -q`
Expected: FAIL — `ImportError: cannot import name 'redact_responsive'`.

- [ ] **Step 3: Add the alias**

In `scripts/_style.py`, immediately after the existing `redact_pseudo_state = redact_theme` (line 141) and its comment block, append:

```python
# Regime-3c: responsive multi-viewport reflow deltas share the same
# {width_label: {prop: raw value}} delta shape, so they reuse the redactor. Alias
# (NOT a wrapper) so the two can never drift. Values are CSS keywords/lengths/track-
# lists (no content/url in the RESPONSIVE_PROPS universe), so the redactor is a near-
# no-op here, but the alias keeps firewall recursion + canary symmetry with theme.
redact_responsive = redact_theme
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_style.py -q`
Expected: PASS (all `test_style.py` tests, including the two new).

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_responsive alias for Regime-3c reflow deltas"
```

---

### Task 2: `RESPONSIVE_PROPS` constant + generalize `_snapshot_recs`

**Files:**
- Modify: `scripts/web_skeleton.py` (constants after `PSEUDO_STATES` line 91; `_snapshot_recs` at line 620)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_web_skeleton.py`, add:

```python
def test_responsive_props_curated_excludes_continuous_px():
    # The curated discrete-layout set: props that FLIP at author breakpoints, plus
    # font-size (the clamp() fluid curve). Continuous px are deliberately excluded —
    # bbox already carries rendered size and they would delta on nearly every node in
    # fluid layouts (the anti-chimera choice, design §2.1).
    for p in ("display", "flex-direction", "flex-wrap", "grid-template-columns",
              "grid-template-rows", "gap", "column-gap", "row-gap", "position",
              "font-size", "text-align"):
        assert p in ws.RESPONSIVE_PROPS
    for p in ("width", "height", "margin-top", "padding-top", "top", "left", "inset"):
        assert p not in ws.RESPONSIVE_PROPS


def test_snapshot_recs_requests_given_prop_list(monkeypatch):
    # _snapshot_recs(ev, props) must request AND parse exactly `props`; the default is
    # WANT_STYLES (theme/pseudo paths unchanged). Regime-3c passes RESPONSIVE_PROPS
    # (which is NOT a subset of WANT_STYLES), so the parameter must thread through both
    # the captureSnapshot computedStyles AND the parse_snapshot call.
    import web_skeleton as W
    seen = {}

    class FakeSess:
        def send(self, method, params):
            if method == "DOMSnapshot.captureSnapshot":
                seen["props"] = params["computedStyles"]
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None

    monkeypatch.setattr(W, "parse_snapshot",
                        lambda snap, props, dpr: ("parsed", list(props)))
    out = W._snapshot_recs(FakeEv(), W.RESPONSIVE_PROPS)
    assert seen["props"] == W.RESPONSIVE_PROPS           # captureSnapshot got the list
    assert out == ("parsed", list(W.RESPONSIVE_PROPS))   # parse_snapshot got the SAME list
    W._snapshot_recs(FakeEv())                           # default
    assert seen["props"] == W.WANT_STYLES
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_responsive_props_curated_excludes_continuous_px test_web_skeleton.py::test_snapshot_recs_requests_given_prop_list -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'RESPONSIVE_PROPS'` and the generalized signature not yet present.

- [ ] **Step 3: Add the constants**

In `scripts/web_skeleton.py`, after the `PSEUDO_STATES = ("hover", "focus", "active")` line (line 91) and its comment, add:

```python
# Regime-3c: responsive multi-viewport reflow diff. RESPONSIVE_PROPS = the curated
# DISCRETE-layout props that flip at author @media/@container breakpoints
# (display/flex-*/grid-template-*/gap/position/text-align) plus font-size (the clamp()
# fluid curve). Continuous px (width/height/margin/padding/inset) are deliberately
# EXCLUDED — bbox already carries rendered size and they delta on nearly every node in
# fluid layouts (anti-chimera, design §2.1). NOT a subset of WANT_STYLES, so the
# breakpoint captures request this list explicitly via _snapshot_recs(ev, props).
RESPONSIVE_PROPS = ["display", "flex-direction", "flex-wrap", "grid-template-columns",
                    "grid-template-rows", "gap", "column-gap", "row-gap", "position",
                    "font-size", "text-align"]
DEFAULT_BREAKPOINTS = "390,768,1440"
```

- [ ] **Step 4: Generalize `_snapshot_recs`**

In `scripts/web_skeleton.py`, change `_snapshot_recs` (line 620) to take a `props` parameter defaulting to `WANT_STYLES`:

```python
def _snapshot_recs(ev, props=WANT_STYLES):
    """REST + ONE DOMSnapshot.captureSnapshot + parse → records. NO navigate — the
    caller flips Emulation.setEmulatedMedia / CSS.forcePseudoState / device-metrics
    width between calls. Shared by _styles_by_backend (theme + pseudo-state, default
    WANT_STYLES) and Regime-3c capture_with_breakpoints (RESPONSIVE_PROPS, which is NOT
    a subset of WANT_STYLES — hence the parameter). `props` threads through BOTH the
    captureSnapshot computedStyles whitelist and the parse_snapshot read so the two
    never diverge. dpr is irrelevant here (style-only; bbox unused)."""
    ev.ev(_REST_JS)
    time.sleep(0.15)
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": props, "includeDOMRects": True,
                         "includePaintOrder": True})
    return parse_snapshot(snap, props, dpr=1.0)
```

`_styles_by_backend(ev)` (line 635) still calls `_snapshot_recs(ev)` with no `props`, so the theme/pseudo paths get the WANT_STYLES default — behavior unchanged.

- [ ] **Step 5: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q`
Expected: PASS (all, including the two new). The default-arg generalization must not break any existing `_snapshot_recs`/`_styles_by_backend` test.

- [ ] **Step 6: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add RESPONSIVE_PROPS + generalize _snapshot_recs prop list"
```

---

### Task 3: `apply_node_responsive` + bundle threading

**Files:**
- Modify: `scripts/bundle_writer.py` (`apply_node_pseudo_state` ends ~line 191; `assemble` line 193; `main` pops ~line 277)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_bundle_writer.py`, add after the `test_apply_node_pseudo_state_*` tests:

```python
def test_apply_node_responsive_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_resp = {0: {"768": {"display": "block",
                             "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_responsive(nodes, node_resp)
    assert nodes[0]["responsive"]["768"]["display"] == "block"
    assert nodes[0]["responsive"]["768"]["background-image"] == 'url("<asset>")'
    assert "responsive" not in nodes[1]            # no entry -> no field


def test_apply_node_responsive_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_responsive(nodes, None)
    bw.apply_node_responsive(nodes, {})
    assert "responsive" not in nodes[0]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_responsive_attaches_redacted_delta -q`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_responsive'`.

- [ ] **Step 3: Add `apply_node_responsive`**

In `scripts/bundle_writer.py`, immediately after `apply_node_pseudo_state` (ends ~line 191) and before `def assemble`, add:

```python
def apply_node_responsive(nodes, node_resp):
    """Attach each node's responsive reflow-delta map as node["responsive"], redacted
    by _style (layout keywords/lengths/track-lists kept verbatim; any external/data
    url() -> url("<asset>") as a belt). node_resp: {node_id: {width_label: {prop: raw
    value}}}. Runs BEFORE cf.redact_node, which preserves the `responsive` key (not a
    CONTENT_KEYS entry; redact_node filters only top-level keys, so the nested redacted
    map survives). No entry -> no field. DISTINCT from the bundle-level `states` (G4)
    artifact and from --viewports `sizing` (coarse fill/fixed inference)."""
    if not node_resp:
        return
    for n in nodes:
        rv = node_resp.get(n["id"])
        if rv:
            n["responsive"] = _style.redact_responsive(rv)
```

- [ ] **Step 4: Thread through `assemble`**

Change the `assemble` signature (lines 193–194) to add a trailing `node_responsive=None` and call `apply_node_responsive` after `apply_node_pseudo_state`:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None,
             node_responsive=None):
```

Inside `assemble`, after the existing `apply_node_pseudo_state(nodes, node_pseudo_state)` line (line 204), add:

```python
    apply_node_responsive(nodes, node_responsive)
```

(Order: after `apply_node_pseudo_state`, before `motion = match_motion(...)` and `cf.redact_node`.)

- [ ] **Step 5: Thread through `main`**

In `scripts/bundle_writer.py` `main`, after the `raw_pseudo_state` / `node_pseudo_state` lines (277–278) and before `skeleton.pop("_node_backend", None)` (line 279), add:

```python
    raw_responsive = skeleton.pop("_node_responsive", {})
    node_responsive = {int(k): v for k, v in raw_responsive.items()}
```

Then extend the `assemble(...)` call (lines 286–290) to pass it — add to the final kwargs:

```python
                      node_theme=node_theme, node_pseudo_state=node_pseudo_state,
                      node_responsive=node_responsive)
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: PASS (all, including the two new). The `assemble` default-None addition must not break any existing assemble/round-trip test.

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: thread responsive reflow deltas through bundle assemble"
```

---

### Task 4: Firewall prose canary into `responsive`

**Files:**
- Modify: `scripts/test_content_firewall.py`
- `scripts/content_firewall.py` — **UNCHANGED** (no new content vector; `audit_bundle`'s key-aware walk already recurses arbitrary nested dicts).

- [ ] **Step 1: Write the failing test**

In `scripts/test_content_firewall.py`, add (mirror the `pseudo_state` canary):

```python
def test_audit_canary_unredacted_prose_in_responsive_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["responsive"][width_label][prop]: an un-redacted PROSE leak under a
    # responsive prop trips ONLY via _prose_in_json/_walk_strings (the flat
    # _CONTENT_URL/_DATA_URI/_B64_BLOB detectors do NOT match plain prose). If
    # redact_responsive ever failed to redact a content value (e.g. a leaked author
    # grid-line name run), THIS is the backstop that must catch it. Mirrors the theme
    # and pseudo_state prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "responsive": {
                         "768": {"display": "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in responsive delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves responsive recursion), not a flat detector"
```

- [ ] **Step 2: Run to verify it passes immediately**

Run: `cd scripts && python3 -m pytest test_content_firewall.py::test_audit_canary_unredacted_prose_in_responsive_trips -q`
Expected: **PASS without touching `content_firewall.py`** — the canary asserts the EXISTING key-aware walker already reaches `node.responsive[label][prop]`. (This is a TDD inversion: the test confirms an existing invariant holds for the new key. If it FAILS, the walker does not recurse into unknown keys and the design's firewall-backstop claim is wrong — STOP and escalate.)

- [ ] **Step 3: Run the full firewall suite**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: add firewall prose canary for responsive reflow deltas"
```

---

### Task 5: `capture_with_breakpoints` + `--breakpoints` flag

**Files:**
- Modify: `scripts/web_skeleton.py` (new function after `capture_with_pseudo_states` ~line 746; argparse + branch in `main`)
- Test: `scripts/test_web_skeleton.py`

**Model:** integration/judgment task (multi-step CDP orchestration) — dispatch with a capable model (opus).

- [ ] **Step 1: Write the failing tests**

In `scripts/test_web_skeleton.py`, add:

```python
def test_capture_with_breakpoints_wires_override_diff_clear(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    node_backend = {0: 5}
    # base captured at the WIDEST width via _capture_one(width=base_w); it owns that
    # override, so the loop emulates ONLY the narrower widths.
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, node_backend))
    calls = []

    def fake_recs(ev, props=None):
        calls.append(1)
        # 1st call = base (1440) -> display:flex; 2nd = 768 width -> display:block
        style = {"display": "flex"} if len(calls) == 1 else {"display": "block"}
        return [{"backend": 5, "pseudo": None, "style": style}]

    monkeypatch.setattr(W, "_snapshot_recs", fake_recs)

    sk = W.capture_with_breakpoints(ev, "chrome", "http://x", [1440, 768])

    # sidecar = diffed delta, keyed by node id (string), under the width label; backend internal.
    assert sk["_node_responsive"] == {"0": {"768": {"display": "block"}}}
    overrides = [p for (m, p) in ev.sess.sent
                 if m == "Emulation.setDeviceMetricsOverride"]
    assert any(p["width"] == 768 for p in overrides)           # narrower width emulated
    assert ("Emulation.clearDeviceMetricsOverride", {}) in ev.sess.sent  # cleaned up in finally
    # no re-navigate inside the loop: the only ev.ev driver is _snapshot_recs (monkeypatched);
    # capture_with_breakpoints itself issues no Page.navigate / location.assign.


def test_capture_with_breakpoints_emulates_each_width_widest_first(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))
    # identical styles at every width -> no delta -> empty sidecar (no crash)
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [{"backend": 5, "pseudo": None, "style": {"gap": "0px"}}])

    sk = W.capture_with_breakpoints(ev, "chrome", "http://x", [768, 1440, 390])
    widths = [p["width"] for (m, p) in ev.sess.sent
              if m == "Emulation.setDeviceMetricsOverride"]
    # widest (1440) is the base (via _capture_one, not re-emulated); the loop emulates the
    # narrower widths in descending order.
    assert widths == [768, 390]
    assert sk["_node_responsive"] == {}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_breakpoints_wires_override_diff_clear -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'capture_with_breakpoints'`.

- [ ] **Step 3: Add `capture_with_breakpoints`**

In `scripts/web_skeleton.py`, after `capture_with_pseudo_states` (ends ~line 746) and before `def _capture_one`, add:

```python
def capture_with_breakpoints(ev, engine, url, widths, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton at the WIDEST width, then for each narrower width
    re-emulate the viewport (Emulation.setDeviceMetricsOverride, NO navigate) and diff
    full resolved styles vs base over RESPONSIVE_PROPS; attach per-width deltas as the
    _node_responsive sidecar (keyed by node id; backendNodeId stays internal).

    Width override is GLOBAL (one condition per capture), so — unlike the per-node
    forcePseudoState path — there is no co-occurrence chimera and no
    DOM.pushNodesByBackendIdsToFrontend round-trip. backendNodeId is stable across the
    overrides on one navigate (probe R2) so base↔width join exactly. Base + every width
    use identical capture params over RESPONSIVE_PROPS (phantom-diff guard, design §3):
    the base skeleton itself is captured with WANT_STYLES by _capture_one for the normal
    bundle, while the diff reads (base + each width) all use RESPONSIVE_PROPS — the two
    prop lists never cross. CDP-only (Emulation.setDeviceMetricsOverride); the caller
    guards on hasattr(ev, "sess"). Clears the metrics override in `finally` so the
    operator's tab is left unpolluted.

    Drop-on-miss: a node display:none at a width (or removed by a JS resize listener) is
    absent from that width's capture and dropped for it (style-only ceiling, design §6).
    @container rides free only for viewport-tracking containers (probe R7)."""
    try:
        widths = sorted(set(widths), reverse=True)   # widest first = the base reference
        base_w, delta_ws = widths[0], widths[1:]
        sk, _layout, _page, node_backend = _capture_one(ev, engine, url, width=base_w,
                                                         max_wait=max_wait)
        # base diff-styles at base_w (override still set by _capture_one; no navigate)
        base_styles = _theme.styles_by_backend(_snapshot_recs(ev, RESPONSIVE_PROPS))
        per_width = {}
        for w in delta_ws:
            ev.sess.send("Emulation.setDeviceMetricsOverride",
                         {"width": int(w), "height": 900, "deviceScaleFactor": 1,
                          "mobile": False})
            time.sleep(0.25)   # let the @media/@container reflow settle before recapture
            cond_styles = _theme.styles_by_backend(_snapshot_recs(ev, RESPONSIVE_PROPS))
            delta = _theme.diff_theme(base_styles, cond_styles, RESPONSIVE_PROPS)
            per_width[str(w)] = _theme.rekey_by_node_id(delta, node_backend)
        node_resp = _theme.build_node_theme(per_width)
        sk["_node_responsive"] = {str(k): v for k, v in node_resp.items()}
        return sk
    finally:
        try:
            ev.sess.send("Emulation.clearDeviceMetricsOverride", {})
        except Exception:
            pass
```

- [ ] **Step 4: Run the orchestration tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_breakpoints_wires_override_diff_clear test_web_skeleton.py::test_capture_with_breakpoints_emulates_each_width_widest_first -q`
Expected: PASS both.

- [ ] **Step 5: Add the `--breakpoints` flag + branch**

In `scripts/web_skeleton.py` `main`, register the flag immediately after the `--pseudo-states` argument (before `--max-wait`):

```python
    p.add_argument("--breakpoints", nargs="?", const=DEFAULT_BREAKPOINTS, default=None,
                   help="comma widths e.g. 390,768,1440 (bare --breakpoints uses the "
                        "default 390,768,1440); capture per-node resolved-style REFLOW "
                        "deltas across viewport widths (Emulation.setDeviceMetricsOverride, "
                        "backendNodeId join) into the _node_responsive sidecar. DISTINCT "
                        "from --viewports (coarse fill/fixed sizing inference, positional "
                        "join, merged skeleton).")
```

Add the handler branch AFTER the `elif args.pseudo_states:` block and BEFORE `elif args.viewports:`:

```python
    elif args.breakpoints:
        try:
            widths = [int(w) for w in args.breakpoints.split(",") if w.strip()]
        except ValueError:
            die(f"web_skeleton --breakpoints: widths must be integers, got "
                f"{args.breakpoints!r} (e.g. --breakpoints 390,768,1440)")
        if not widths or any(w <= 0 for w in widths):
            die("web_skeleton --breakpoints needs >=1 positive integer width "
                "(e.g. --breakpoints 390,768,1440)")
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --breakpoints needs a CDP transport "
                    "(Emulation.setDeviceMetricsOverride). Use chrome host / --cdp-port.")
            out_obj = capture_with_breakpoints(ev, engine, args.url, widths,
                                               max_wait=args.max_wait)
        finally:
            ev.close()
```

Note: `--breakpoints` joins the existing mutually-exclusive `if/elif` chain — passing it together with `--themes`/`--pseudo-states`/`--viewports` runs only the first matched, consistent with the landed pattern (documented, not a regression).

- [ ] **Step 6: Static-check the parse (no CDP)**

Run: `cd scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Then `python3 -m pytest test_web_skeleton.py -q` → PASS (full file; the CLI branch is exercised end-to-end by the host gate in Task 6, which only the controller runs).

- [ ] **Step 7: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add capture_with_breakpoints and --breakpoints flag"
```

---

### Task 6: Host CDP gate (controller-run)

**Files:**
- Create: `fixtures/responsive/run_responsive.py`

**Implementer:** write the file and static-check it (`python3 -c "import ast; ast.parse(...)"`). Do NOT run it (CDP unreachable from the ctx sandbox). The CONTROLLER runs it on host Bash with `dangerouslyDisableSandbox=true`.

- [ ] **Step 1: Write the gate**

Create `fixtures/responsive/run_responsive.py`:

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --breakpoints captures per-node resolved-style REFLOW deltas
across viewport widths (Emulation.setDeviceMetricsOverride, NO re-navigate), and the
pipeline redacts them content-free. PROVES JOIN CORRECTNESS: the @media node gets the
RIGHT narrow-width display/flex/font-size delta; a clamp() node's font-size re-resolves;
a viewport-tracking @container node re-evals ONLY at the width where its container drops
below threshold (design §6 / probe R7); a node with NO responsive rule gets NO delta
(per-width isolation); a grid-template
change with author-named lines flows through the firewall (caught-not-silent — a SILENT
prose leak would trip audit_bundle and FAIL this gate loudly). Deterministic, offline
(local server). Runs on host CDP. bundle_writer.write_bundle runs the firewall audit and
RAISES on leak."""
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

# Base = widest (1200). @media (max-width:600px) fires at the narrow widths (400 + 280);
# @container (max-width:300px) on a viewport-tracking container fires only at 280 (the
# container is a full-width block ~= viewport, so ~280 < 300 but ~400 > 300). Fixed px
# sizes (width/height) so nodes are identifiable by bbox regardless of viewport.
_PAGE = """<!doctype html><meta charset=utf-8><title>resp-gate</title>
<style>
 #known { display:flex; flex-direction:row; font-size:24px; width:300px; height:50px; }
 @media (max-width:600px){ #known { display:block; flex-direction:column; font-size:12px; } }
 #fluid  { font-size: clamp(10px,5vw,40px); width:200px; height:30px; }
 #static { display:block; font-size:16px; width:80px; height:40px; }
 #grid   { display:grid; grid-template-columns:[a] 100px [b] 100px; width:260px; height:70px; }
 @media (max-width:600px){ #grid { grid-template-columns:[a] 1fr; } }
 #cqwrap { container-type: inline-size; }   /* block: inline size tracks the viewport */
 #cq     { font-size:18px; width:120px; height:25px; }
 @container (max-width:300px){ #cq { font-size:9px; } }
</style>
<div id=known>k</div><div id=fluid>f</div><div id=static>s</div><div id=grid>g</div>
<div id=cqwrap><div id=cq>c</div></div>"""

_SIZE = {"known": (300.0, 50.0), "fluid": (200.0, 30.0),
         "static": (80.0, 40.0), "grid": (260.0, 70.0), "cq": (120.0, 25.0)}
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
    sk = json.loads((Path(bundle_dir) / "skeleton.json").read_text())
    nodes = sk.get("nodes") or []

    # On-disk regression locks: backendNodeId is the INTERNAL join key and must NEVER
    # reach disk; the responsive carrier sidecar is internal too. The per-node
    # `responsive` field IS expected (that's the feature).
    assert "_node_responsive" not in sk, \
        "GATE FAIL: internal carrier _node_responsive leaked to disk"
    assert "_node_backend" not in sk, \
        "GATE FAIL: internal join-key sidecar _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), \
        "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("responsive"), \
        "GATE FAIL: #known has no responsive delta"
    d400 = known["responsive"].get("400", {})
    assert d400.get("display") == "block", \
        f"GATE FAIL: #known @400 display delta wrong: {d400}"
    assert d400.get("flex-direction") == "column", \
        f"GATE FAIL: #known @400 flex-direction delta wrong: {d400}"
    assert d400.get("font-size") == "12px", \
        f"GATE FAIL: #known @400 font-size delta wrong: {d400}"
    assert "1200" not in known["responsive"], \
        "GATE FAIL: base width 1200 must not appear as a delta label"

    fluid = _node_by_size(nodes, _SIZE["fluid"])
    assert fluid is not None and fluid.get("responsive", {}).get("400"), \
        "GATE FAIL: #fluid clamp() font-size did not re-resolve at 400"
    # clamp(10px,5vw,40px): 5vw of 400 = 20px (within range)
    assert fluid["responsive"]["400"].get("font-size") == "20px", \
        f"GATE FAIL: #fluid @400 clamp font-size wrong: {fluid['responsive']['400']}"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("responsive"), \
        f"GATE FAIL: #static got a spurious responsive delta (isolation): {static.get('responsive')}"

    grid = _node_by_size(nodes, _SIZE["grid"])
    assert grid is not None and grid.get("responsive", {}).get("400"), \
        "GATE FAIL: #grid grid-template-columns did not delta at 400"
    assert "grid-template-columns" in grid["responsive"]["400"], \
        f"GATE FAIL: #grid @400 missing grid-template-columns: {grid['responsive']['400']}"

    # @container (viewport-tracking): #cq re-evals ONLY at 280 (container ~280 < 300),
    # NOT at 400 (container ~400 > 300). Proves viewport-tracking @container rides free
    # (design §6 / probe R7) AND per-width isolation, in one node.
    cq = _node_by_size(nodes, _SIZE["cq"])
    assert cq is not None and cq.get("responsive", {}).get("280"), \
        "GATE FAIL: #cq viewport-tracking @container did not re-eval at 280"
    assert cq["responsive"]["280"].get("font-size") == "9px", \
        f"GATE FAIL: #cq @280 @container font-size wrong: {cq['responsive']['280']}"
    assert "400" not in cq.get("responsive", {}), \
        "GATE FAIL: #cq must NOT delta at 400 (container ~400 > 300; @container not fired)"

    print("GATE PASS: responsive join correct (#known carries the right narrow-width "
          "display/flex-direction/font-size reflow delta; #fluid clamp font-size "
          "re-resolved to 20px@400; #grid grid-template-columns delta flowed through the "
          "firewall; #cq viewport-tracking @container fired ONLY at 280; #static isolated "
          "— no delta); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "responsive" / "_bundle"
    sk_json = ROOT / "fixtures" / "responsive" / "_sk.json"
    tok_json = ROOT / "fixtures" / "responsive" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--breakpoints", "1200,400,280", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Static-check (implementer)**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 -c "import ast; ast.parse(open('fixtures/responsive/run_responsive.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Implementer does NOT execute the gate.

- [ ] **Step 3: Commit (implementer)**

```bash
git add fixtures/responsive/run_responsive.py
git commit -m "test: add Regime-3c responsive host gate fixture"
```

- [ ] **Step 4: CONTROLLER runs the gate on host**

Controller only (host Bash, `dangerouslyDisableSandbox=true`):
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/responsive/run_responsive.py`
Expected: `GATE PASS: ...`. If `bundle_writer FAILED (content leak?)` due to the `#grid` named-line value tripping the prose canary, that is the caught-not-silent fallback firing — apply the design §6 fallback (drop `grid-template-columns`/`grid-template-rows` from `RESPONSIVE_PROPS`) in its OWN commit, re-run the gate, and note it in the docs after-task. If `#known`/`#fluid` asserts fail, the @media/clamp re-eval premise is broken — STOP and escalate (contradicts probe R1/R3).

---

## After-tasks (CONTROLLER only — run after Task 6 gate PASS)

These are NOT plan tasks; the controller executes them directly (host Bash for CDP).

1. **Regime-3a theme gate + 3b pseudo-state gate regression** (the `_snapshot_recs` generalization touches the shared helper — prove no regression):
   `python3 fixtures/theme/run_theme.py` → `GATE PASS`; `python3 fixtures/pseudo-state/run_pseudo_state.py` → `GATE PASS`.
2. **Full unit suite:** `cd scripts && python3 -m pytest -q` → all green (366 baseline + new T1/T2/T3/T4/T5 tests).
3. **Real-site validation harness** — create `fixtures/responsive/validate_realsite.py` (content-free: prints ONLY host netloc + per-width nodes-with-delta + volume % + changed-prop NAMES + counts; NO content / resolved values / full URL; `bundle_writer` raising = caught leak). Mirror `fixtures/pseudo-state/validate_realsite.py` with `LABELS` = the delta widths (e.g. `["768", "390"]` for `--breakpoints 1440,768,390`). Commit (`test: add Regime-3c content-free real-site validation harness`). Controller runs it against ≥1 public responsive site; audit must be CLEAN; report content-free signal only.
4. **Docs** — add `§C9-R-P11 — Regime-3c responsive multi-viewport LANDED` to `docs/plans/probe-runner-engine-capture-gaps.md` and update its roadmap-status footer (P11 landed; remove Regime-3c from Remaining). Flip the `@media` / `@container` / `clamp()` rows in `docs/research/css-capture-completeness.md` §9 to LANDED (3c) and update the intro update-log. Commit (`docs: record Regime-3c responsive capture (P11) landed`).
5. **Final code review** — dispatch a final reviewer subagent over the whole commit range; fix any Critical/Important in its OWN commit.
6. **Advisor done-gate**, then report DONE and await the go signal for the next rung. Do NOT push. Do NOT auto-start the next rung.

---

## Self-Review

**1. Spec coverage:** §1 probe → premise behind T5 capture flow (gate T6 re-confirms R1/R3/R5). §2.1 RESPONSIVE_PROPS → T2. §2.2 sidecar shape → T3/T5. §3 capture flow (base via `_capture_one` widest, diff via generalized `_snapshot_recs`, loop no-navigate, clear in finally) → T2 (generalize) + T5 (function). §4 backendNodeId join, never on disk → T5 + T6 on-disk locks. §5 `_theme` reuse unchanged → T5 (no `_theme` edit). §6 ceilings: drop-on-miss (diff_theme, documented in T5 docstring), grid named-line firewall watch-item (T6 gate + §6 fallback), @container viewport-tracking — **gate-proven** (T6 `#cq` node fires at 280, isolated at 400) + T5 docstring; fixed-width @container deferred. §7 bundle + firewall UNCHANGED → T3 + T4. §8 testing → T1–T6 + after-tasks. §9 CLI `--breakpoints` → T5. §10 distinction from `--viewports` → T5 help text + `apply_node_responsive` docstring.

**2. Placeholder scan:** none — every code step carries complete code; the only described-not-coded item is the real-site harness (after-task), which references the existing `fixtures/pseudo-state/validate_realsite.py` as the exact pattern to mirror (content shown there; not a plan task).

**3. Type/name consistency:** `RESPONSIVE_PROPS` (list), `DEFAULT_BREAKPOINTS` (str), `_snapshot_recs(ev, props=WANT_STYLES)`, `capture_with_breakpoints(ev, engine, url, widths, max_wait=...)`, `_node_responsive` (sidecar key), `responsive` (per-node field), `redact_responsive` (alias), `apply_node_responsive(nodes, node_resp)`, `assemble(..., node_responsive=None)`, `--breakpoints` flag — names identical across every task. Width labels are `str(w)`; `main` re-keys node ids via `int(k)` (matches the theme/pseudo_state pop pattern). The gate imports no unused symbols (no `parse_color` — 3c asserts no colors).
