# Regime-3b Interactive States Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. CAVEMAN MODE is active for chat; **plan/code/commits are written normally.**

**Goal:** Capture each element's resolved CSS style **delta** under three forced interactive pseudo-class states — `:hover`, `:focus`, `:active` — as an additive per-node `pseudo_state` sidecar, joined by `backendNodeId`, content-free, with no reproduction-side parser.

**Architecture:** A structural clone of Regime-3a (theme/preference). The join key (`backendNodeId` → `node_backend`), the pure diff core (`_theme.diff_theme`/`rekey_by_node_id`/`build_node_theme`), and the redactor pattern are all LANDED and **reused unchanged**. The one new axis is the forcing mechanism: instead of one global `Emulation.setEmulatedMedia` flip per condition, force a **per-element** `CSS.forcePseudoState` on every element node, take one recapture per state, and diff. A throwaway host probe verified the load-bearing facts (see design §1): a forced pseudo-state survives a fresh `DOMSnapshot`; `pushNodesByBackendIdsToFrontend` round-trips the join key to the CDP `nodeId`; force-all is cheap (~0.2 ms/call) and isolation-correct.

**Tech Stack:** Python 3 stdlib; Chrome DevTools Protocol via `_web_eval`/`_web` (`DOMSnapshot.captureSnapshot`, `DOM.pushNodesByBackendIdsToFrontend`, `CSS.forcePseudoState`); pytest for pure-core units; a local `http.server` + host Chrome integration harness (`fixtures/pseudo-state/run_pseudo_state.py`) for the browser path. No new dependencies.

**Design spec:** `docs/plans/regime3b-interactive-states-capture-design.md`.

**Naming (critical):** the per-node field is `pseudo_state`, NOT `states`. A bundle-level `states.json`/`bundle["states"]` already exists for the unrelated **G4 interaction-state** capture (`web_states.py`; click-driven component reveals; `fixtures/interaction-state/`). Keep the two distinct. The `assemble(...)` function already has a `states=None` param for G4 — do NOT reuse it; add a separate `node_pseudo_state=None` param.

**Standing constraints (every task):**
- Commits SINGLE-LINE, no body, no trailers, no `Co-Authored-By`.
- Stage files EXPLICITLY by path; never `git add -A`/`git add .`.
- ONE commit per task; a review-driven fix gets its own commit.
- Do NOT push — all work local on `master`.
- `backendNodeId` is INTERNAL — never written to disk.
- `content_firewall.py` stays UNCHANGED (no new content vector).
- Implementer subagents do NOT run the host CDP gate (CDP is unreachable from the ctx sandbox). They write the gate file and static-check it (`python3 -c "import ast; ast.parse(open(path).read())"`). The CONTROLLER runs the gate on host Bash with `dangerouslyDisableSandbox=true`.

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `scripts/_style.py` | Modify (after `redact_theme`) | Add `redact_pseudo_state = redact_theme` alias. |
| `scripts/web_skeleton.py` | Modify | Add `PSEUDO_STATES`, `element_backends`, `_snapshot_recs` (refactor `_styles_by_backend` onto it), `capture_with_pseudo_states`, and the `--pseudo-states` CLI branch. |
| `scripts/bundle_writer.py` | Modify | Add `apply_node_pseudo_state`; thread `node_pseudo_state` through `assemble` + `main`. |
| `scripts/test_style.py` | Modify | Alias-identity + functional pass-through tests. |
| `scripts/test_web_skeleton.py` | Modify | `element_backends` filter test + `capture_with_pseudo_states` orchestration unit (fake CDP). |
| `scripts/test_bundle_writer.py` | Modify | `apply_node_pseudo_state` attach/none-safe tests. |
| `scripts/test_content_firewall.py` | Modify | Prose canary under `node["pseudo_state"]`. |
| `fixtures/pseudo-state/run_pseudo_state.py` | Create | Host CDP gate: join correctness + per-state isolation + no-disk-leak. |

---

## Task 1: `redact_pseudo_state` alias (`_style.py`)

**Model:** cheap/mechanical.

**Files:**
- Modify: `scripts/_style.py` (immediately after `redact_theme`, ~line 135)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_style.py`. First extend the existing `_style` import line 7 from:
```python
from _style import redact_theme  # noqa: E402
```
to:
```python
from _style import redact_theme, redact_pseudo_state  # noqa: E402
```
Then append these tests:
```python
def test_redact_pseudo_state_is_redact_theme_alias():
    # Regime-3b pseudo-class deltas share the theme delta shape exactly; the redactor
    # is the SAME function (alias, not a copy) so the two can never drift.
    assert redact_pseudo_state is redact_theme


def test_redact_pseudo_state_redacts_external_url_keeps_rgb():
    out = redact_pseudo_state({"hover": {"color": "rgb(0, 128, 0)",
                                         "background-image": 'url("https://a/b.png")'}})
    assert out["hover"]["color"] == "rgb(0, 128, 0)"           # raw rgb kept
    assert out["hover"]["background-image"] == 'url("<asset>")'  # external url redacted
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_pseudo_state_is_redact_theme_alias -v`
Expected: FAIL — `ImportError: cannot import name 'redact_pseudo_state'`.

- [ ] **Step 3: Add the alias**

In `scripts/_style.py`, immediately after the `redact_theme` function (the file currently ends right after it), add:
```python


# Regime-3b: forced pseudo-class (:hover/:focus/:active) deltas share the theme-delta
# shape ({condition_or_state_label: {prop: raw value}}) byte-for-byte, so they share the
# redactor. Alias (NOT a wrapper) so the two can never drift. DISTINCT from the
# bundle-level `states` (G4 interaction-state) artifact — this is per-node CSS restyle.
redact_pseudo_state = redact_theme
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_style.py -q`
Expected: PASS (all `test_style.py` tests, including the two new ones).

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_pseudo_state alias for Regime-3b pseudo-class deltas"
```

---

## Task 2: `element_backends` + `_snapshot_recs` + `PSEUDO_STATES` (`web_skeleton.py`)

**Model:** cheap/mechanical.

**Files:**
- Modify: `scripts/web_skeleton.py` (`PSEUDO_STATES` near `THEME_PROPS` ~line 85; `element_backends` + `_snapshot_recs` near `_styles_by_backend` ~line 614)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test**

Append to `scripts/test_web_skeleton.py` (the module is imported at the top as `import web_skeleton as ws`):
```python
def test_element_backends_filters_non_elements():
    # forcePseudoState rejects non-elements ("Node is not an Element"), so the force
    # set must keep ELEMENT records only: tag present and not '#…', not a pseudo
    # record, backend present. styles_by_backend keeps text/doc nodes — this does not.
    recs = [
        {"tag": "DIV", "backend": 5, "pseudo": None, "style": {}},
        {"tag": "#text", "backend": 6, "pseudo": None, "style": {}},      # text node
        {"tag": "SPAN", "backend": 7, "pseudo": "::before", "style": {}},  # pseudo record
        {"tag": "BUTTON", "backend": None, "pseudo": None, "style": {}},   # no backend
        {"tag": "A", "backend": 9, "pseudo": None, "style": {}},
        {"tag": "#document", "backend": 1, "pseudo": None, "style": {}},   # document
    ]
    assert ws.element_backends(recs) == [5, 9]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_element_backends_filters_non_elements -v`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'element_backends'`.

- [ ] **Step 3: Add `PSEUDO_STATES`, `element_backends`, and `_snapshot_recs`**

In `scripts/web_skeleton.py`, directly after the `THEME_PROPS = ...` line (~line 85), add:
```python

# Regime-3b: forced interactive pseudo-class states. The diff universe is THEME_PROPS
# verbatim (already covers color/background-color/box-shadow/outline-*/text-decoration —
# host probe F1/F1b confirmed; `cursor` deferred). Forced via CSS.forcePseudoState; the
# forcedPseudoClasses value is the bare name (no colon).
PSEUDO_STATES = ("hover", "focus", "active")
```

Then locate `_styles_by_backend` (~line 614). Replace this exact function:
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
```
with:
```python
def _snapshot_recs(ev):
    """REST + ONE DOMSnapshot.captureSnapshot + parse → records. NO navigate — the
    caller flips Emulation.setEmulatedMedia or CSS.forcePseudoState between calls.
    Shared by _styles_by_backend (theme + pseudo-state) and the base pass of
    capture_with_pseudo_states (which also needs the per-record `tag` for the element
    force-set). dpr is irrelevant here (style-only; bbox unused)."""
    ev.ev(_REST_JS)
    time.sleep(0.15)
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WANT_STYLES, "includeDOMRects": True,
                         "includePaintOrder": True})
    return parse_snapshot(snap, WANT_STYLES, dpr=1.0)


def _styles_by_backend(ev):
    """{backendNodeId: full resolved style dict} for element+text nodes at the page's
    CURRENT emulation/forced-state + REST. Behavior-identical wrapper over
    _snapshot_recs (DRY)."""
    return _theme.styles_by_backend(_snapshot_recs(ev))


def element_backends(recs):
    """backendNodeIds for ELEMENT records only — `tag` present and not starting with
    '#' (excludes #text/#document/#comment), not a pseudo record, `backend` present.
    forcePseudoState rejects non-elements ("Node is not an Element"), so the
    force-set must exclude the text/doc nodes that _theme.styles_by_backend keeps
    (host probe). Pure over parse_snapshot records → unit-testable."""
    out = []
    for r in recs:
        b = r.get("backend")
        tag = r.get("tag") or ""
        if b is None or r.get("pseudo") or not tag or tag.startswith("#"):
            continue
        out.append(b)
    return out
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q`
Expected: PASS (the new test + every existing `test_web_skeleton.py` test — the `_styles_by_backend` refactor is behavior-preserving).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add element_backends and _snapshot_recs for Regime-3b force set"
```

---

## Task 3: `apply_node_pseudo_state` + bundle threading (`bundle_writer.py`)

**Model:** cheap/mechanical. **Depends on Task 1** (`redact_pseudo_state`).

**Files:**
- Modify: `scripts/bundle_writer.py` (`apply_node_pseudo_state` after `apply_node_theme` ~line 176; `assemble` sig ~178 + body ~188; `main` pop ~259)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test_bundle_writer.py` (`import bundle_writer as bw` is at the top):
```python
def test_apply_node_pseudo_state_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_ps = {0: {"hover": {"color": "rgb(0, 128, 0)",
                             "background-image": 'url("https://a/b.png")'}}}
    bw.apply_node_pseudo_state(nodes, node_ps)
    assert nodes[0]["pseudo_state"]["hover"]["color"] == "rgb(0, 128, 0)"
    assert nodes[0]["pseudo_state"]["hover"]["background-image"] == 'url("<asset>")'
    assert "pseudo_state" not in nodes[1]            # no entry -> no field


def test_apply_node_pseudo_state_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_pseudo_state(nodes, None)
    assert "pseudo_state" not in nodes[0]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_pseudo_state_attaches_redacted_delta -v`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_pseudo_state'`.

- [ ] **Step 3: Implement**

In `scripts/bundle_writer.py`, directly after the `apply_node_theme` function (ends ~line 176), add:
```python


def apply_node_pseudo_state(nodes, node_ps):
    """Attach each node's forced-pseudo-class (:hover/:focus/:active) delta map as
    node["pseudo_state"], redacted by _style (external/data url() -> url("<asset>");
    raw rgb kept). node_ps: {node_id: {state_label: {prop: raw value}}}. Runs BEFORE
    cf.redact_node, which preserves the `pseudo_state` key (not a CONTENT_KEYS entry;
    redact_node filters only top-level keys, so the nested redacted map survives).
    No entry -> no field. DISTINCT from the bundle-level `states` (G4) artifact."""
    if not node_ps:
        return
    for n in nodes:
        pv = node_ps.get(n["id"])
        if pv:
            n["pseudo_state"] = _style.redact_pseudo_state(pv)
```

Change the `assemble` signature (~line 178) from:
```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None):
```
to:
```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None):
```
and in the body, directly after the `apply_node_theme(nodes, node_theme)` line (~line 188), add:
```python
    apply_node_pseudo_state(nodes, node_pseudo_state)
```

In `main` (~line 259), directly after these existing lines:
```python
    raw_theme = skeleton.pop("_node_theme", {})
    node_theme = {int(k): v for k, v in raw_theme.items()}
```
add:
```python
    raw_pseudo_state = skeleton.pop("_node_pseudo_state", {})
    node_pseudo_state = {int(k): v for k, v in raw_pseudo_state.items()}
```
and add `node_pseudo_state=node_pseudo_state` to the `assemble(...)` call (~line 272). It currently ends with `node_theme=node_theme)`; change to `node_theme=node_theme, node_pseudo_state=node_pseudo_state)`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: PASS (new tests + all existing).

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: emit per-node pseudo_state sidecar in bundle_writer"
```

---

## Task 4: firewall prose canary for `pseudo_state` (`test_content_firewall.py`)

**Model:** cheap/mechanical. Test-only — `content_firewall.py` is UNCHANGED. **Depends on Task 3** (the `pseudo_state` field shape exists).

**Files:**
- Test: `scripts/test_content_firewall.py` (append near the `theme` canaries ~line 425)

- [ ] **Step 1: Write the test**

Append to `scripts/test_content_firewall.py` (uses the existing `_clean_bundle` helper and `import content_firewall as cf`):
```python
def test_audit_canary_unredacted_prose_in_pseudo_state_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["pseudo_state"][label][prop]: an un-redacted PROSE leak under a pseudo-state
    # prop trips ONLY via _prose_in_json/_walk_strings (the flat _CONTENT_URL/_DATA_URI/
    # _B64_BLOB detectors do NOT match plain prose). If redact_pseudo_state ever failed
    # to redact a content value, THIS is the backstop that must catch it. Mirrors the
    # theme prose canary.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "pseudo_state": {
                         "hover": {"content": "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in pseudo_state delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves pseudo_state recursion), not a flat detector"
```

- [ ] **Step 2: Run to verify it passes immediately**

The firewall already walks all keys, so this test passes without any product change — that IS the point (it locks the existing behavior for the new field).
Run: `cd scripts && python3 -m pytest test_content_firewall.py::test_audit_canary_unredacted_prose_in_pseudo_state_trips -v`
Expected: PASS.

- [ ] **Step 3: Sanity-check it is meaningful (not vacuous)**

Confirm the assertion is real by temporarily checking the violation kind: the prose string contains no url/data:/base64, so it can ONLY trip via the prose walk. (No edit needed — just confirm the test passed for the right reason; the `kind == "prose"` assertion enforces this.)

- [ ] **Step 4: Run the full firewall suite**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: lock pseudo_state prose leak trips firewall key-aware walk"
```

---

## Task 5: `capture_with_pseudo_states` + `--pseudo-states` CLI (`web_skeleton.py`)

**Model:** standard/integration (opus). **Depends on Task 2** (`element_backends`/`_snapshot_recs`/`PSEUDO_STATES`) and the LANDED `_theme` core.

**Files:**
- Modify: `scripts/web_skeleton.py` (`capture_with_pseudo_states` after `capture_with_themes` ~line 660; `--pseudo-states` argparse + `main` branch ~line 728/744)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing orchestration test**

Append to `scripts/test_web_skeleton.py`. This drives `capture_with_pseudo_states` with a fake CDP transport — no browser — and asserts the force/clear/diff/build wiring:
```python
def test_capture_with_pseudo_states_wires_force_diff_clear(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self):
            self.sent = []

        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                # backendNodeId -> nodeId (deterministic: nodeId = 100 + backend)
                return {"nodeIds": [100 + b for b in params["backendNodeIds"]]}
            return {}

    class FakeEv:
        def __init__(self):
            self.sess = FakeSess()

        def ev(self, expr):
            return None

        def close(self):
            pass

    ev = FakeEv()
    # base: one element DIV (backend 5) at node id 0.
    base_recs = [{"tag": "DIV", "backend": 5, "pseudo": None,
                  "style": {"color": "rgb(0, 0, 0)"}}]
    node_backend = {0: 5}
    monkeypatch.setattr(W, "_capture_one",
                        lambda ev, engine, url, max_wait=None: ({"nodes": [{"id": 0}]},
                                                                None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs", lambda ev: base_recs)
    # forced recapture: the DIV's color changes under :hover.
    monkeypatch.setattr(W, "_styles_by_backend",
                        lambda ev: {5: {"color": "rgb(1, 1, 1)"}})

    sk = W.capture_with_pseudo_states(ev, "chrome", "http://x", ["hover"])

    # sidecar built with the diffed delta, keyed by node id (string), backend internal.
    assert sk["_node_pseudo_state"] == {"0": {"hover": {"color": "rgb(1, 1, 1)"}}}
    # forced the bare pseudo name on the mapped nodeId (100 + 5), then CLEARED it.
    forces = [p for (m, p) in ev.sess.sent if m == "CSS.forcePseudoState"]
    assert {"nodeId": 105, "forcedPseudoClasses": ["hover"]} in forces
    assert {"nodeId": 105, "forcedPseudoClasses": []} in forces
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_pseudo_states_wires_force_diff_clear -v`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'capture_with_pseudo_states'`.

- [ ] **Step 3: Implement `capture_with_pseudo_states`**

In `scripts/web_skeleton.py`, directly after the `capture_with_themes` function (it ends with the `finally: ev.sess.send("Emulation.setEmulatedMedia", {"features": []})` block, ~line 659) and before `def _capture_one(...)`, add:
```python


def capture_with_pseudo_states(ev, engine, url, labels, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton, then for each interactive pseudo-class `label`
    (hover/focus/active) FORCE that state on EVERY element node, recapture, and diff
    full resolved styles vs base (THEME_PROPS); attach per-state deltas as the
    _node_pseudo_state sidecar (keyed by node id; backendNodeId stays internal).

    Force-all-elements: cheap (~0.2 ms/forcePseudoState call — host probe F5) and
    isolation-correct (a node with no rule for the state gets no delta — probe F4),
    and it captures ancestor-hover-chain `.menu:hover .item` patterns a leaf-only set
    would miss (probe F3). Base + every state use identical capture params
    (phantom-diff guard). CDP-only (CSS.forcePseudoState); the caller guards on
    hasattr(ev, "sess"). Clears all forced state in `finally` so the operator's tab
    is left unpolluted (the analogue of capture_with_themes clearing emulation)."""
    sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
    recs = _snapshot_recs(ev)                          # base; tags needed for element set
    base_styles = _theme.styles_by_backend(recs)
    elem = element_backends(recs)
    ev.sess.send("DOM.enable", {})
    ev.sess.send("CSS.enable", {})
    ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})
    pushed = ev.sess.send("DOM.pushNodesByBackendIdsToFrontend",
                          {"backendNodeIds": elem})
    node_ids = pushed.get("nodeIds") or []
    # backendNodeId -> CDP nodeId; drop any zero/falsy id defensively.
    force_ids = [nid for nid in node_ids if nid]
    try:
        per_state = {}
        for label in labels:
            for nid in force_ids:
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": [label]})
            time.sleep(0.2)   # let the forced restyle settle before recapture
            cond_styles = _styles_by_backend(ev)
            delta = _theme.diff_theme(base_styles, cond_styles, THEME_PROPS)
            per_state[label] = _theme.rekey_by_node_id(delta, node_backend)
            for nid in force_ids:    # clear so the next state starts from base
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": []})
        node_ps = _theme.build_node_theme(per_state)
        sk["_node_pseudo_state"] = {str(k): v for k, v in node_ps.items()}
        return sk
    finally:
        for nid in force_ids:
            try:
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": []})
            except Exception:
                pass
```

- [ ] **Step 4: Run the orchestration test to verify it passes**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_pseudo_states_wires_force_diff_clear -v`
Expected: PASS.

- [ ] **Step 5: Add the `--pseudo-states` flag and `main` branch**

In `scripts/web_skeleton.py` `main`, add the argparse flag directly after the existing `--themes` argument (~line 728):
```python
    p.add_argument("--pseudo-states", default=None, dest="pseudo_states",
                   help="comma labels from {hover,focus,active}; capture per-node "
                        "resolved style deltas under each forced CSS pseudo-class "
                        "(CSS.forcePseudoState) into the _node_pseudo_state sidecar")
```
Then add an `elif` branch directly after the `if args.themes:` block closes (after its `finally: ev.close()`, before `elif args.viewports:`):
```python
    elif args.pseudo_states:
        labels = [s.strip() for s in args.pseudo_states.split(",") if s.strip()]
        bad = [l for l in labels if l not in PSEUDO_STATES]
        if bad:
            die(f"web_skeleton --pseudo-states: unknown {bad}; choose from "
                f"{sorted(PSEUDO_STATES)}")
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --pseudo-states needs a CDP transport "
                    "(CSS.forcePseudoState). Use chrome host / --cdp-port.")
            out_obj = capture_with_pseudo_states(ev, engine, args.url, labels,
                                                 max_wait=args.max_wait)
        finally:
            ev.close()
```

- [ ] **Step 6: Static-check and run the full web_skeleton suite**

Run: `cd scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('ast-ok')" && python3 -m pytest test_web_skeleton.py -q`
Expected: `ast-ok` then PASS (all tests). (The live `--pseudo-states` browser path is exercised by the host gate in Task 6, not here.)

- [ ] **Step 7: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: capture forced hover/focus/active deltas via --pseudo-states"
```

---

## Task 6: host CDP gate (`fixtures/pseudo-state/run_pseudo_state.py`)

**Model:** standard/integration (opus) to WRITE the file; the CONTROLLER runs it on host.

**Files:**
- Create: `fixtures/pseudo-state/run_pseudo_state.py`

- [ ] **Step 1: Write the gate script**

Create `fixtures/pseudo-state/run_pseudo_state.py` with exactly:
```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --pseudo-states captures per-node resolved style deltas
under forced :hover / :focus / :active (CSS.forcePseudoState), and the pipeline redacts
them content-free. PROVES JOIN CORRECTNESS: the :hover node gets the RIGHT hover delta;
a :focus node gets an outline delta; the #menu:hover .child descendant gets the
combinator delta; a node with NO interactive rule gets NO delta (per-state isolation).
Deterministic, offline (local server). Runs on host CDP. bundle_writer.write_bundle
runs the firewall audit and RAISES on leak."""
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
from web_tokens import parse_color  # noqa: E402  (format-robust rgb compare)

# #known restyles under hover (color/bg) + focus (outline) + active (color).
# #static has NO interactive rule -> MUST get no pseudo_state delta.
# #menu:hover .child -> descendant-combinator restyle of #child.
_PAGE = """<!doctype html><meta charset=utf-8><title>pstate-gate</title>
<style>
 #known { width:120px; height:60px; color: rgb(10,20,30);
          background-color: rgb(200,200,200); outline-style: none; }
 #known:hover { color: rgb(0,128,0); background-color: rgb(17,17,17); }
 #known:focus { outline-style: solid; outline-color: rgb(255,0,0); outline-width: 3px; }
 #known:active { color: rgb(0,0,255); }
 #static { width:80px; height:40px; color: rgb(50,60,70);
           background-color: rgb(123,124,125); }
 #menu:hover .child { color: rgb(123,45,67); }
 #child { width:40px; height:20px; color: rgb(1,2,3); }
</style>
<div id=known tabindex="0">k</div>
<div id=menu><div id=child class=child>c</div></div>
<div id=static>s</div>"""
# tabindex="0" on #known makes :focus unambiguous on a non-interactive <div>
# (forcePseudoState applies :focus regardless, but this removes any doubt the
# focus assertion failing would be div-focusability, not product code). No bbox or
# color change. :hover/:active need no such guard.

# Identify emitted nodes by their fixed rendered bbox size (deterministic for this page;
# background-color lives in a stripped sidecar, not node["style"], so size is the key).
_SIZE = {"known": (120.0, 60.0), "static": (80.0, 40.0), "child": (40.0, 20.0)}
_SIZE_TOL = 2.0  # px


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

    # On-disk regression locks: backendNodeId is the INTERNAL join key (session-scoped +
    # mild fingerprint) and must NEVER reach disk. It is a bare int, so it trips NO
    # firewall content-pattern — these asserts over the real serialized bundle are the
    # only backstop. The per-node `pseudo_state` field IS expected (that's the feature).
    assert "_node_backend" not in sk, \
        "GATE FAIL: internal join-key sidecar _node_backend leaked to disk"
    assert "_node_pseudo_state" not in sk, \
        "GATE FAIL: internal carrier _node_pseudo_state leaked to disk"
    assert all("backend" not in n for n in nodes), \
        "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("pseudo_state"), \
        "GATE FAIL: #known has no pseudo_state"
    ps = known["pseudo_state"]
    # hover: color + bg restyle.
    hov = ps.get("hover", {})
    assert parse_color(hov.get("color")) == (0, 128, 0), \
        f"GATE FAIL: wrong hover color delta: {hov.get('color')}"
    assert parse_color(hov.get("background-color")) == (17, 17, 17), \
        f"GATE FAIL: wrong hover bg delta: {hov.get('background-color')}"
    # focus: outline ring.
    foc = ps.get("focus", {})
    assert foc.get("outline-style") == "solid", \
        f"GATE FAIL: focus outline-style not captured: {foc}"
    assert parse_color(foc.get("outline-color")) == (255, 0, 0), \
        f"GATE FAIL: wrong focus outline-color: {foc.get('outline-color')}"
    # active: color restyle.
    act = ps.get("active", {})
    assert parse_color(act.get("color")) == (0, 0, 255), \
        f"GATE FAIL: wrong active color delta: {act.get('color')}"

    # JOIN CORRECTNESS: descendant combinator. #menu:hover .child restyles #child under
    # hover, proving the hover delta lands on the right node via the combinator.
    child = _node_by_size(nodes, _SIZE["child"])
    assert child is not None and child.get("pseudo_state"), \
        "GATE FAIL: #child has no pseudo_state (descendant-combinator delta missing)"
    assert parse_color(child["pseudo_state"].get("hover", {}).get("color")) == (123, 45, 67), \
        f"GATE FAIL: wrong #child hover delta: {child['pseudo_state'].get('hover')}"

    # PER-STATE ISOLATION: #static has NO interactive rule, so force-all must leave it
    # with NO hover/focus/active delta — proving deltas land only on nodes whose rule
    # fired, never smeared across the tree (probe F4).
    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("pseudo_state"), \
        f"GATE FAIL: #static got a spurious pseudo_state: {static.get('pseudo_state')}"

    print("GATE PASS: pseudo-state join correct (#known carries right hover/focus/"
          "active deltas; #child carries the descendant-combinator hover delta; #static "
          "isolated — no delta); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "pseudo-state" / "_bundle"
    sk_json = ROOT / "fixtures" / "pseudo-state" / "_sk.json"
    tok_json = ROOT / "fixtures" / "pseudo-state" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url,
         "--pseudo-states", "hover,focus,active",
         "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json),
         "--tokens", str(tok_json),
         "--out", str(out)],
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

Run: `cd scripts && python3 -c "import ast; ast.parse(open('../fixtures/pseudo-state/run_pseudo_state.py').read()); print('ast-ok')"`
Expected: `ast-ok`. (The implementer does NOT run the gate — CDP is unreachable from the sandbox. Report DONE for controller to run it.)

- [ ] **Step 3: Commit**

```bash
git add fixtures/pseudo-state/run_pseudo_state.py
git commit -m "test: add Regime-3b pseudo-state host gate (join, isolation, no-disk-leak)"
```

---

## After all tasks (controller, not implementer subagents)

These mirror the Regime-3a close-out. The controller runs them in order:

1. **Run the host gate** on host Bash (`dangerouslyDisableSandbox=true`):
   `cd <repo> && python3 fixtures/pseudo-state/run_pseudo_state.py`
   Expected: `GATE PASS: ...`. If it FAILS, diagnose (test-expectation bug vs product bug) before continuing; a product-code fix is its own commit + re-run. Clean up the gate's `_bundle`/`_sk.json`/`_tokens.json` artifacts after (do not commit them).
   **Also re-run the Regime-3a theme gate** (`python3 fixtures/theme/run_theme.py` → `GATE PASS`) once here: Task 2 refactored `_styles_by_backend` (shared with the LANDED theme path), and the unit suite does not cover the theme *host gate* — this is the regression check the shared-code change implies.

2. **Full suite:** `cd scripts && python3 -m pytest -q`. Expect all green (prior baseline 358 + the new Regime-3b tests).

3. **Real-site validation harness:** create `fixtures/pseudo-state/validate_realsite.py` (mirror `fixtures/theme/validate_realsite.py`: `LABELS = ["hover", "focus", "active"]`, invoke `web_skeleton.py --pseudo-states <labels>` then `bundle_writer.py`; print ONLY content-free signal — host/netloc, total element nodes, per-state nodes-with-delta count + volume %, changed-prop NAMES + counts; never values/selectors/urls). Run it on one public page on host CDP, confirm the audit is CLEAN at scale and the bundle stays bounded. **Coverage sanity:** unresolved `pushNodesByBackendIdsToFrontend` ids are silently dropped (those nodes get no delta). If nodes-with-delta looks suspiciously low vs total elements, that drop is the prime suspect — surface the element-count vs delta-count so a low ratio is visible, not hidden. Print/persist only content-free signal.

4. **Docs:**
   - `docs/plans/probe-runner-engine-capture-gaps.md`: add a `§C9-R-P10` section (join key reused; force-all mechanism; probe F1–F7 facts; ceilings; real-site result) and update the roadmap-status footer (Regime-3b LANDED; remaining 3c responsive + Regime-4).
   - `docs/research/css-capture-completeness.md`: flip the `:hover`, `:focus`/`:focus-visible`, `:active` rows to **LANDED (3b)** (note `:focus-visible`/form states deferred) and update the ranked-list / Regime-3 header note.

5. **Final code review** (opus): whole-implementation review against the spec — content-free invariant (pseudo_state values: redactor + firewall + prose canary; join key: orchestration unit + on-disk gate asserts), firewall unchanged, no `states`/`pseudo_state` collision, all tests green.

6. **advisor done-gate** before declaring complete.

---

## Self-Review (writing-plans checklist)

**1. Spec coverage:** §2 scope → Tasks 1–6; §3 capture flow → Task 5; §4 join → reused (Task 2 element map + Task 5); §5 diff core reuse → Task 5 (no new module); §6 redaction → Task 1; §7 bundle → Task 3; §8 firewall unchanged → Task 4 (lock only); §9 ceilings → docs after-task; §10 testing → Tasks 1–6 tests + after-tasks 1–3; §11 CLI → Task 5. No gaps.

**2. Placeholder scan:** none — every code step shows complete code; every run step shows the exact command + expected result.

**3. Type/name consistency:** `pseudo_state` (field), `_node_pseudo_state` (carrier), `redact_pseudo_state` (alias), `apply_node_pseudo_state`, `capture_with_pseudo_states`, `element_backends`, `_snapshot_recs`, `PSEUDO_STATES`, `--pseudo-states`/`dest=pseudo_states`, `node_pseudo_state` (assemble param) — used identically across Tasks 1–6 and the gate. `build_node_theme`/`diff_theme`/`rekey_by_node_id` reused with their landed names. No `states` collision with the G4 artifact.
