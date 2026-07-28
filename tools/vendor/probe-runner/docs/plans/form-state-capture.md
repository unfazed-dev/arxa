# Form-state pseudo-class capture (`:checked`/`:disabled`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The
> CONTROLLER (not the subagent) runs every host CDP gate with the sandbox disabled; subagents do
> pure work + unit tests + a static AST parse only.

**Goal:** Capture the per-node computed-style DELTA when a form control is forced into `:checked`
/ `:disabled`, content-free, joined by `backendNodeId`, as a `form_state` sidecar.

**Architecture:** Near-clone of the reduced-motion (P13) rung for the sidecar/redactor/bundle
path, plus R3b's force-then-clear discipline — BUT the force-set is restricted to state-eligible
elements via `DOM.querySelectorAll` per state (the probe proved force-all smears bare rules onto
non-eligible nodes). New `FORM_PROPS` universe = `THEME_PROPS + opacity + accent-color + cursor`.

**Tech Stack:** Python 3, CDP (`CSS.forcePseudoState`, `DOM.querySelectorAll`,
`DOMSnapshot.captureSnapshot`), pytest. Pure `_theme` core reused verbatim.

**Design spec:** `docs/plans/form-state-capture-design.md` (probe-grounded, commits `06aa81b`,
`65277e6`). Read §0 (FS-series facts) and §2 (mechanism) before Task 4.

---

## STANDING CONSTRAINTS (verbatim-critical — every task)

- **Commits:** SINGLE-LINE, NO trailers, NO `Co-Authored-By`, NO body. ONE commit per task; a
  review-driven fix gets its OWN commit.
- **Staging:** stage files EXPLICITLY by path. NEVER `git add -A` / `git add .`.
- **Do NOT push.** All work local on `master`.
- **Host CDP gates** (Task 5 + after-tasks) run on host Bash with the sandbox disabled (CDP is
  unreachable from the ctx sandbox). Implementer subagents WRITE the gate/harness files and
  static-check only (`python3 -c "import ast; ast.parse(open('<path>').read())"`); the CONTROLLER
  runs the live CDP gate.
- **Content firewall IP boundary — never persist/print copyrighted/third-party content.** The
  real-site harness prints/persists ONLY content-free signal (prop NAMES + COUNTS + host netloc;
  never content values, resolved strings, selectors, or full URLs). Failure paths print returncode
  only — NEVER subprocess stderr (a `ContentLeak` message can embed a content sample).
- **`backendNodeId`** (and transient CDP `nodeId`) are INTERNAL — never on disk.
- **`content_firewall.py`: REVISED during Task 3** (was planned UNCHANGED). The prose canary passed
  against the existing key-aware walker, but the `cursor` url() canary surfaced a real PRE-EXISTING
  gap — the url() detector was extension-allowlisted, missing `url(x.cur)` / non-media-ext external
  asset URLs inside delta values. Fix landed as its own commit (`fc440d5`): `_CSS_URL_REF`
  url()-wrapper detector. The TDD inversion did its job — the deviation is correct, flagged, and
  verified (all 5 gates + 32-test firewall suite green).

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `scripts/_style.py` | `redact_form_state = redact_theme` alias | T1 |
| `scripts/test_style.py` | alias test | T1 |
| `scripts/bundle_writer.py` | `apply_node_form_state` + `assemble` kwarg + `main` pop | T2 |
| `scripts/test_bundle_writer.py` | apply tests | T2 |
| `scripts/test_content_firewall.py` | prose canary + cursor `url()` canary | T3 |
| `scripts/web_skeleton.py` | `FORM_PROPS`, `FORM_STATE_SELECTORS`, `capture_with_form_states`, `--form-states` | T4 |
| `scripts/test_web_skeleton.py` | props/selectors/capture-diff/error-clear tests | T4 |
| `fixtures/form-state/run_form_state.py` | host CDP gate (controller-run) | T5 |
| `fixtures/form-state/validate_realsite.py` | content-free real-site harness | after-tasks |
| `.gitignore` | fixture runtime artifacts | after-tasks |
| `docs/plans/probe-runner-engine-capture-gaps.md` | §C9-R-P14 results + roadmap footer | after-tasks |

---

## Task 1: `redact_form_state` alias (`_style.py`)

**Files:**
- Modify: `scripts/_style.py` (after the `redact_reduced_motion` alias, `_style.py:150-155`)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing test** — append to `scripts/test_style.py` after
  `test_redact_reduced_motion_is_redact_theme_alias`:

```python
def test_redact_form_state_is_redact_theme_alias():
    # form_state is a flat {label:{prop:value}} delta (labels "checked"/"disabled"), identical in
    # shape to a theme delta -> the redactor is the SAME function (alias), like
    # redact_reduced_motion / redact_pseudo_state / redact_responsive.
    assert redact_form_state is redact_theme
    out = redact_form_state({"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                             "disabled": {"opacity": "0.4", "cursor": "not-allowed"}})
    assert out == {"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                   "disabled": {"opacity": "0.4", "cursor": "not-allowed"}}
    assert redact_form_state(None) is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_form_state_is_redact_theme_alias -q`
Expected: FAIL — `NameError: name 'redact_form_state' is not defined`.

- [ ] **Step 3: Add the alias** — in `scripts/_style.py`, immediately AFTER the existing
  `redact_reduced_motion = redact_theme` line (currently `_style.py:155`):

```python


# Form-state (:checked/:disabled): the per-node delta is the flat {label:{prop:value}} theme
# shape (labels "checked"/"disabled"), so its redactor is the SAME walker — an alias, exactly
# like redact_reduced_motion / redact_pseudo_state / redact_responsive. (Contrast
# redact_keyframes, which needed its own walker for the [{timing,frames}] shape.)
redact_form_state = redact_theme
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_form_state_is_redact_theme_alias -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_form_state alias for the form-state delta"
```

---

## Task 2: Thread the form-state delta through bundle assemble (`bundle_writer.py`)

**Files:**
- Modify: `scripts/bundle_writer.py` (after `apply_node_reduced_motion` `:225-238`; `assemble`
  signature `:240-242`; call site `:255`; `main` pop `:339-340`; `assemble(...)` call `:348-354`)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_bundle_writer.py` after
  `test_apply_node_reduced_motion_none_safe`:

```python
def test_apply_node_form_state_attaches_redacted_delta():
    nodes = [{"id": 0}, {"id": 1}]
    node_fs = {0: {"checked": {"opacity": "0.5", "accent-color": "rgb(11, 22, 33)"},
                   "disabled": {"opacity": "0.4", "cursor": "not-allowed"}}}
    bw.apply_node_form_state(nodes, node_fs)
    assert nodes[0]["form_state"]["checked"]["accent-color"] == "rgb(11, 22, 33)"
    assert nodes[0]["form_state"]["disabled"]["cursor"] == "not-allowed"
    assert "form_state" not in nodes[1]        # no entry -> no field


def test_apply_node_form_state_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_form_state(nodes, None)
    bw.apply_node_form_state(nodes, {})
    assert "form_state" not in nodes[0]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -q -k apply_node_form_state`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_form_state'`.

- [ ] **Step 3: Add `apply_node_form_state`** — in `scripts/bundle_writer.py`, immediately AFTER
  the `apply_node_reduced_motion` function (after `bundle_writer.py:238`), before `def assemble`:

```python
def apply_node_form_state(nodes, node_fs):
    """Attach each node's form-state computed-style delta as node["form_state"], redacted by
    _style (flat {label:{prop:value}} shape; redact_form_state is a redact_theme alias).
    node_fs: {node_id: {"checked": {prop: value}, "disabled": {prop: value}}}. Runs BEFORE
    cf.redact_node, which preserves the `form_state` key (not a CONTENT_KEYS entry). No entry /
    empty delta -> no field. Sibling to the theme/pseudo_state/responsive/reduced_motion deltas
    (same shape). Combinator deltas (e.g. `:checked ~ .panel`) land on the SIBLING node's id."""
    if not node_fs:
        return
    for n in nodes:
        fv = node_fs.get(n["id"])
        if fv:
            n["form_state"] = _style.redact_form_state(fv)
```

- [ ] **Step 4: Add the `assemble` kwarg + call.** In the `assemble` signature (currently ends
  `..., node_keyframes=None, node_reduced_motion=None):` at `bundle_writer.py:240-242`), append a
  trailing param so it reads:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
```
(keep the existing first line) and change the LAST line of the signature from
`             node_responsive=None, node_keyframes=None, node_reduced_motion=None):`
to:
```python
             node_responsive=None, node_keyframes=None, node_reduced_motion=None,
             node_form_state=None):
```

Then, immediately AFTER the existing `apply_node_reduced_motion(nodes, node_reduced_motion)` call
(`bundle_writer.py:255`), add:

```python
    apply_node_form_state(nodes, node_form_state)
```

- [ ] **Step 5: Wire `main`.** In `bundle_writer.py` `main`, immediately AFTER the two
  `_node_reduced_motion` lines (`:339-340`) and BEFORE `skeleton.pop("_node_backend", None)`:

```python
    raw_form_state = skeleton.pop("_node_form_state", {})
    node_form_state = {int(k): v for k, v in raw_form_state.items()}
```

Then extend the `assemble(...)` call (`:348-354`) — change the final argument line from
`                      node_reduced_motion=node_reduced_motion)`
to:
```python
                      node_reduced_motion=node_reduced_motion,
                      node_form_state=node_form_state)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -q -k apply_node_form_state`
Expected: PASS (2 passed).

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: thread form-state delta through bundle assemble"
```

---

## Task 3: Firewall canaries — prose + cursor `url()` (TDD inversion)

**OUTCOME (post-execution):** the prose canary passed against the existing key-aware
`_walk_strings` (it already reaches `node["form_state"][label][prop]`). The `cursor` url() canary
FAILED against the unchanged firewall — surfacing a real PRE-EXISTING extension-allowlist gap — so
`content_firewall.py` WAS revised (`_CSS_URL_REF`, own commit `fc440d5`) and the canary was
corrected to the real json-escaped serialized shape (`url(\"https…`) to avoid a false green.

**Files:**
- Test: `scripts/test_content_firewall.py` (after
  `test_audit_canary_unredacted_prose_in_reduced_motion_trips`, `:482`)

- [ ] **Step 1: Write the canary tests** — append to `scripts/test_content_firewall.py`:

```python
def test_audit_canary_unredacted_prose_in_form_state_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["form_state"][label][prop]: an un-redacted PROSE leak there trips ONLY via the
    # key-aware prose walk (flat URL/base64 detectors do NOT match plain prose). Backstop if
    # redact_form_state ever failed. Mirrors the reduced_motion/theme/pseudo_state canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "form_state": {"checked": {"accent-color":
                                                "This is leaked prose content here now"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a form_state delta must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves form_state recursion), not a flat detector"


def test_audit_canary_cursor_url_in_form_state_trips(tmp_path):
    # cursor is the new prop in FORM_PROPS; `cursor: url(...)` can embed a path -> a content
    # vector. Prove the firewall's existing URL detector is the backstop for it.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "form_state": {"disabled":
                                    {"cursor": "url(https://evil.example.com/secret/path.cur), auto"}}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "a cursor url() in a form_state delta must trip the audit"
```

- [ ] **Step 2: Run the canaries — they must PASS against the UNCHANGED firewall**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -q -k form_state`
Expected: PASS (2 passed). If EITHER fails, STOP — the firewall does not cover the
`form_state` field (prose) or `cursor` url() (content vector); that is a real gap requiring a
firewall fix, NOT a test edit. Report it.

- [ ] **Step 3: Confirm `content_firewall.py` is untouched**

Run: `git diff --stat scripts/content_firewall.py`
Expected: NO output (zero changes).

- [ ] **Step 4: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: add firewall prose + cursor url() canaries for form-state delta"
```

---

## Task 4: `capture_with_form_states` + `--form-states` flag (`web_skeleton.py`)

Read design spec §2 first. This is the integration task.

**Files:**
- Modify: `scripts/web_skeleton.py` (constants after `MOTION_PROPS` `:118-125`;
  `capture_with_form_states` after `capture_with_reduced_motion` `:884-912`; flag after
  `--reduced-motion` `:1004-1009`; branch after the `elif args.reduced_motion:` block `:1075-1083`)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_web_skeleton.py` after
  `test_capture_with_reduced_motion_clears_emulation_on_error`:

```python
def test_form_props_and_selectors_curated():
    import web_skeleton as W
    # FORM_PROPS = THEME_PROPS + the three probe-confirmed additions; layout props absent.
    for p in ("opacity", "accent-color", "cursor", "color", "background-color",
              "outline-color"):
        assert p in W.FORM_PROPS
    for p in ("width", "height", "display", "position", "animation-name"):
        assert p not in W.FORM_PROPS
    # eligibility selectors encode state-eligible element types exactly (incl. input type).
    assert W.FORM_STATE_SELECTORS["checked"] == "input[type=checkbox], input[type=radio], option"
    assert W.FORM_STATE_SELECTORS["disabled"] == \
        "input, button, select, textarea, fieldset, optgroup, option"


def test_capture_with_form_states_diffs_per_state(monkeypatch):
    import web_skeleton as W

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            if method == "DOM.getDocument":
                return {"root": {"nodeId": 1}}
            if method == "DOM.querySelectorAll":
                return {"nodeIds": [10, 11]}     # eligible nodes (frontend ids)
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

    # _snapshot_recs called 3x: base, then checked cond, then disabled cond.
    base = [
        {"backend": 5, "pseudo": None, "style": {"opacity": "1", "accent-color": "auto",
            "cursor": "default", "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
            "outline-color": "rgb(0, 0, 0)"}},
        {"backend": 7, "pseudo": None, "style": {"opacity": "1", "accent-color": "auto",
            "cursor": "default", "color": "rgb(0, 0, 0)", "background-color": "rgba(0, 0, 0, 0)",
            "outline-color": "rgb(0, 0, 0)"}}]
    checked = [dict(base[0], style=dict(base[0]["style"], opacity="0.5",
                    **{"accent-color": "rgb(11, 22, 33)"})), base[1]]
    disabled = [dict(base[0], style=dict(base[0]["style"], opacity="0.4", cursor="not-allowed")),
                base[1]]
    seq = {"n": 0, "rows": [base, checked, disabled]}

    def fake_snapshot(ev, props=None):
        r = seq["rows"][seq["n"]]
        seq["n"] += 1
        return r
    monkeypatch.setattr(W, "_snapshot_recs", fake_snapshot)

    sk = W.capture_with_form_states(ev, "chrome", "http://x", ("checked", "disabled"))

    fs = sk["_node_form_state"]
    assert "0" in fs and "1" not in fs                 # node 0 (backend 5) moved; node 1 didn't
    assert fs["0"]["checked"]["opacity"] == "0.5"
    assert fs["0"]["checked"]["accent-color"] == "rgb(11, 22, 33)"
    assert fs["0"]["disabled"]["cursor"] == "not-allowed"
    assert "_node_backend" not in sk                   # internal join key never on the skeleton
    # querySelectorAll used per state with the eligibility selectors
    sels = [p["selector"] for m, p in sent if m == "DOM.querySelectorAll"]
    assert sels == ["input[type=checkbox], input[type=radio], option",
                    "input, button, select, textarea, fieldset, optgroup, option"]
    # every forced node was cleared (forcedPseudoClasses: []) at least as often as it was set
    set_calls = [p for m, p in sent if m == "CSS.forcePseudoState" and p["forcedPseudoClasses"]]
    clr_calls = [p for m, p in sent if m == "CSS.forcePseudoState" and not p["forcedPseudoClasses"]]
    assert len(clr_calls) >= len(set_calls) > 0


def test_capture_with_form_states_clears_forced_on_error(monkeypatch):
    import web_skeleton as W
    import pytest

    sent = []

    class FakeSess:
        def send(self, method, params):
            sent.append((method, params))
            if method == "DOM.getDocument":
                return {"root": {"nodeId": 1}}
            if method == "DOM.querySelectorAll":
                return {"nodeIds": [10]}
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))

    # The BASE snapshot (call 1) happens BEFORE forcing; the exception must land on the COND
    # snapshot (call 2), i.e. AFTER forcePseudoState, so the finally has a forced node to clear.
    calls = {"n": 0}

    def boom(ev, props=None):
        calls["n"] += 1
        if calls["n"] == 1:
            return [{"backend": 5, "pseudo": None, "style": {"opacity": "1"}}]   # base ok
        raise RuntimeError("snapshot failed mid-state")                          # cond -> raises
    monkeypatch.setattr(W, "_snapshot_recs", boom)

    with pytest.raises(RuntimeError):
        W.capture_with_form_states(ev, "chrome", "http://x", ("checked",))
    # node 10 was forced before the cond snapshot raised; finally must clear it.
    assert any(m == "CSS.forcePseudoState" and not p["forcedPseudoClasses"]
               for m, p in sent), "forced pseudo-state must be cleared on error"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q -k form`
Expected: FAIL — `AttributeError: ... has no attribute 'FORM_PROPS'` /
`'capture_with_form_states'`.

- [ ] **Step 3: Add the constants** — in `scripts/web_skeleton.py`, immediately AFTER the
  `MOTION_PROPS = [...]` block (after `web_skeleton.py:125`):

```python

# Form-state (:checked/:disabled): per-node computed-style delta when a form control is forced
# into the state via CSS.forcePseudoState. FORM_PROPS = THEME_PROPS + the three props the probe
# (commits 06aa81b/65277e6, FS4) measured to MOVE: opacity (dimming), accent-color (checkbox
# tint), cursor (not-allowed — user-approved deferral-break). NOT a subset of WANT_STYLES, so it
# is snapshotted explicitly (the capture_with_breakpoints pattern).
FORM_PROPS = THEME_PROPS + ["opacity", "accent-color", "cursor"]

# The force-set is RESTRICTED to state-eligible element types (FS3: force-all smears bare rules
# onto non-eligible nodes). DOM.querySelectorAll encodes eligibility EXACTLY — incl. input `type`,
# which snapshot recs do not carry. `:checked` -> checkboxes/radios/options; `:disabled` ->
# form-associated elements.
FORM_STATE_SELECTORS = {
    "checked": "input[type=checkbox], input[type=radio], option",
    "disabled": "input, button, select, textarea, fieldset, optgroup, option",
}
```

- [ ] **Step 4: Add `capture_with_form_states`** — in `scripts/web_skeleton.py`, immediately AFTER
  the `capture_with_reduced_motion` function (after its `finally` block, `web_skeleton.py:912`),
  before `def _capture_one`:

```python
def capture_with_form_states(ev, engine, url, states, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton, then for each form-state label (checked/disabled) FORCE that
    pseudo-class via CSS.forcePseudoState on ONLY the state-eligible elements (resolved per state
    by DOM.querySelectorAll with FORM_STATE_SELECTORS), recapture FORM_PROPS, and diff vs base;
    attach per-state deltas as the _node_form_state sidecar (keyed by node id; backendNodeId stays
    internal). Mirrors capture_with_reduced_motion (sidecar build via the _theme pure core) +
    capture_with_pseudo_states (force/clear discipline), with the KEY divergence that the
    force-set is targeted, not force-all — the probe (FS3) proved force-all smears bare
    `:disabled{}` / `input:checked{}` rules onto non-eligible nodes (divs, text inputs). The diff
    is over the WHOLE snapshot, so CSS-toggle combinator deltas (`:checked ~ .panel`, FS5) land on
    the non-forced sibling's own backendNodeId.

    FORM_PROPS is snapshotted explicitly (NOT a subset of WANT_STYLES). CDP-only (the caller
    guards on hasattr(ev, "sess")). Ceilings (design §7): DOM.querySelectorAll does not pierce
    shadow DOM / iframes; radio-group mutual exclusion is not modeled. Clears all forced state in
    finally so the operator's tab is left unpolluted."""
    sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
    base = _theme.styles_by_backend(_snapshot_recs(ev, FORM_PROPS))
    ev.sess.send("DOM.enable", {})
    ev.sess.send("CSS.enable", {})
    root = ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})["root"]["nodeId"]
    forced = set()
    try:
        per_state = {}
        for state in states:
            found = ev.sess.send("DOM.querySelectorAll",
                                 {"nodeId": root, "selector": FORM_STATE_SELECTORS[state]})
            ids = [nid for nid in (found.get("nodeIds") or []) if nid]
            for nid in ids:
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": [state]})
                forced.add(nid)
            time.sleep(0.2)   # forced restyle settle (same as capture_with_pseudo_states;
            #                   synchronous same-engine restyle, no navigate -> < 0.3s media flip)
            cond = _theme.styles_by_backend(_snapshot_recs(ev, FORM_PROPS))
            delta = _theme.diff_theme(base, cond, FORM_PROPS)
            per_state[state] = _theme.rekey_by_node_id(delta, node_backend)
            for nid in ids:   # clear so the next state starts from base
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": []})
                forced.discard(nid)
        node_fs = _theme.build_node_theme(per_state)
        sk["_node_form_state"] = {str(k): v for k, v in node_fs.items()}
        return sk
    finally:
        for nid in forced:    # exception mid-state -> leave the tab unpolluted
            try:
                ev.sess.send("CSS.forcePseudoState",
                             {"nodeId": nid, "forcedPseudoClasses": []})
            except Exception:
                pass
```

- [ ] **Step 5: Add the `--form-states` flag** — in `scripts/web_skeleton.py`, immediately AFTER
  the `--reduced-motion` argument block (after `web_skeleton.py:1009`):

```python
    p.add_argument("--form-states", action="store_true", default=False, dest="form_states",
                   help="capture the per-node computed-style delta when form controls are forced "
                        "into :checked / :disabled (CSS.forcePseudoState on state-eligible "
                        "elements via DOM.querySelectorAll, backendNodeId join) into the "
                        "_node_form_state sidecar. Content-free: changed form-state-prop values "
                        "(opacity/accent-color/cursor/color/bg/outline). CSS-toggle combinator "
                        "deltas land on the sibling node.")
```

- [ ] **Step 6: Add the `main` branch** — in `scripts/web_skeleton.py`, immediately AFTER the
  `elif args.reduced_motion:` block (after its `ev.close()` finally, `web_skeleton.py:1083`),
  before `elif args.viewports:`:

```python
    elif args.form_states:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --form-states needs a CDP transport "
                    "(CSS.forcePseudoState / DOM.querySelectorAll). Use chrome host / --cdp-port.")
            out_obj = capture_with_form_states(ev, engine, args.url, ("checked", "disabled"),
                                               max_wait=args.max_wait)
        finally:
            ev.close()
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -q -k form`
Expected: PASS (3 passed).

- [ ] **Step 8: Static-check the whole file parses**

Run: `cd scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('AST OK')"`
Expected: `AST OK`.

- [ ] **Step 9: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add capture_with_form_states and --form-states flag"
```

---

## Task 5: Host CDP gate fixture (implementer WRITES + static-checks; CONTROLLER runs)

**Files:**
- Create: `fixtures/form-state/run_form_state.py`

- [ ] **Step 1: Write the gate.** Create `fixtures/form-state/run_form_state.py` with EXACTLY:

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --form-states captures the per-node computed-style delta when form
controls are forced into :checked / :disabled, and the pipeline redacts it content-free. PROVES:
a checkbox with an input:checked rule (#cb) carries the checked delta; a CSS-toggle combinator
(`#cb:checked ~ #panel`) lands the delta on the PANEL node (FS5 — the dominant :checked use); a
button with a button:disabled rule (#btn) carries the disabled delta (opacity/cursor/bg); a plain
div + a bare `:disabled{}` rule gets NO form_state field (FS3 smear-negative — proves targeting);
a text input + a bare-ish `input:checked{}` rule gets NO checked field (type-targeting); and the
internal join keys never reach disk. Deterministic, offline (local server). bundle_writer
runs the firewall audit and RAISES on leak.

Nodes are identified by distinct rendered bbox size (the motion-gate convention). The on-disk
bbox is the BASE capture (FORM_PROPS has no geometry), so forcing a state cannot move it."""
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

_PAGE = """<!doctype html><meta charset=utf-8><title>form-state-gate</title>
<style>
 /* border-box: form controls render at border-box, so declared w/h == rendered bbox even with
    UA padding/border on <button>/<input> (else content-box inflates them past _SIZE_TOL and
    _node_by_size misses them). FORM_PROPS has no geometry + on-disk bbox is the unforced base
    capture, so forcing a state never moves these. */
 * { box-sizing: border-box; }
 #cb     { width:30px; height:30px; }
 #panel  { width:55px; height:25px; }             /* combinator target (NOT forced) */
 #btn    { width:90px; height:24px; }
 #txt    { width:120px; height:22px; }
 #plain  { width:44px; height:44px; }
 input#cb:checked    { opacity:.5; background-color: rgb(10,20,30); accent-color: rgb(11,22,33); }
 #cb:checked ~ #panel { background-color: rgb(70,80,90); }      /* TOGGLE COMBINATOR -> #panel */
 input:checked        { color: rgb(5,5,5); }       /* bare-ish: must NOT reach #txt (type-target) */
 button#btn:disabled  { opacity:.4; cursor: not-allowed; background-color: rgb(40,50,60); }
 :disabled            { outline: 3px solid rgb(9,9,9); }   /* bare: must NOT reach #plain */
</style>
<input type=checkbox id=cb>
<div id=panel></div>
<input type=text id=txt>
<button id=btn>b</button>
<div id=plain></div>"""

_SIZE = {"cb": (30.0, 30.0), "panel": (55.0, 25.0), "btn": (90.0, 24.0),
         "txt": (120.0, 22.0), "plain": (44.0, 44.0)}
_SIZE_TOL = 3.0


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

    assert "_node_form_state" not in sk, "GATE FAIL: internal carrier _node_form_state leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    cb = _node_by_size(nodes, _SIZE["cb"])
    assert cb is not None and cb.get("form_state"), "GATE FAIL: #cb has no form_state delta"
    ck = cb["form_state"]["checked"]
    assert ck.get("opacity") == "0.5", f"GATE FAIL: #cb checked opacity: {ck}"
    assert ck.get("accent-color") == "rgb(11, 22, 33)", f"GATE FAIL: #cb checked accent-color: {ck}"

    panel = _node_by_size(nodes, _SIZE["panel"])
    assert panel is not None and panel.get("form_state"), \
        "GATE FAIL: combinator sibling #panel has no form_state delta (FS5 toggle-combinator)"
    assert panel["form_state"]["checked"].get("background-color") == "rgb(70, 80, 90)", \
        f"GATE FAIL: #panel combinator delta wrong: {panel['form_state']}"

    btn = _node_by_size(nodes, _SIZE["btn"])
    assert btn is not None and btn.get("form_state"), "GATE FAIL: #btn has no form_state delta"
    ds = btn["form_state"]["disabled"]
    assert ds.get("opacity") == "0.4", f"GATE FAIL: #btn disabled opacity: {ds}"
    assert ds.get("cursor") == "not-allowed", f"GATE FAIL: #btn disabled cursor: {ds}"

    plain = _node_by_size(nodes, _SIZE["plain"])
    assert plain is not None, "GATE FAIL: #plain node missing"
    assert not plain.get("form_state"), \
        f"GATE FAIL: #plain (a div) got a form_state field — bare :disabled{{}} smeared (FS3): {plain.get('form_state')}"

    txt = _node_by_size(nodes, _SIZE["txt"])
    assert txt is not None, "GATE FAIL: #txt node missing"
    assert not (txt.get("form_state") or {}).get("checked"), \
        f"GATE FAIL: #txt (text input) got a checked field — input:checked smeared (type-targeting): {txt.get('form_state')}"

    print("GATE PASS: form-state delta correct (#cb checked opacity/accent-color; #panel "
          "combinator background-color; #btn disabled opacity/cursor; #plain div NO field — "
          "no bare-rule smear; #txt no checked field — type-targeted); backendNodeId never on "
          "disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "form-state" / "_bundle"
    sk_json = ROOT / "fixtures" / "form-state" / "_sk.json"
    tok_json = ROOT / "fixtures" / "form-state" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--form-states", "--out", str(sk_json)],
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

- [ ] **Step 2: Static-check it parses**

Run: `cd <repo root> && python3 -c "import ast; ast.parse(open('fixtures/form-state/run_form_state.py').read()); print('AST OK')"`
Expected: `AST OK`. (The implementer does NOT run the live gate — the CONTROLLER does, host
Bash, sandbox disabled.)

- [ ] **Step 3: Commit**

```bash
git add fixtures/form-state/run_form_state.py
git commit -m "test: add form-state host gate fixture"
```

---

## After-tasks (CONTROLLER ONLY — host Bash, sandbox disabled; NOT a subagent)

These run after all 5 task commits land and the two-stage reviews pass.

- [ ] **A1: Run the host gate**
  `python3 fixtures/form-state/run_form_state.py`  → expect `GATE PASS: ...`.
- [ ] **A2: Regression gates** — R3a/3b/3c/4a/P13 share `_snapshot_recs` / `_capture_one`:
  `python3 fixtures/theme/run_theme.py` (or the established theme gate),
  `python3 fixtures/pseudo-state/run_pseudo_state.py`,
  `python3 fixtures/responsive/run_responsive.py`,
  `python3 fixtures/keyframes/run_keyframes.py`,
  `python3 fixtures/reduced-motion/run_reduced_motion.py` → all expect their PASS line.
  (Run whichever of these exist; report any missing.)
- [ ] **A3: Full unit suite** — `cd scripts && python3 -m pytest -q` → expect all green (prior
  baseline 400; +8 new ⇒ ~408 passed).
- [ ] **A4: gitignore** — add after the `fixtures/reduced-motion/...` block in `.gitignore`:
  ```
  fixtures/form-state/_sk.json
  fixtures/form-state/_tokens.json
  fixtures/form-state/_bundle/
  ```
  Commit: `git add .gitignore && git commit -m "chore: gitignore form-state fixture runtime artifacts"`.
- [ ] **A5: Real-site harness** — create `fixtures/form-state/validate_realsite.py` mirroring
  `fixtures/reduced-motion/validate_realsite.py` (drive `web_skeleton --form-states` →
  `bundle_writer` against `--url`; print ONLY: host netloc, total nodes, nodes-with-form_state
  count, per-state node counts, sorted changed-prop NAME set, per-prop frequency Counter,
  delta-size distribution; on-disk gate check; bundle audit CLEAN/FAILED; failure prints
  returncode ONLY — never subprocess stderr). Run against `https://github.com` (forms-heavy).
  Expect: a HIGH `:disabled` node count is EXPECTED (UA greying, not over-capture — design §6); the
  smear signal to watch is deltas on nodes that are neither state-eligible nor combinator-reachable.
  Commit: `git add fixtures/form-state/validate_realsite.py && git commit -m "test: add form-state content-free real-site validation harness"`.
- [ ] **A6: Docs** — add `## §C9-R-P14 — Results: Form-state (:checked/:disabled) capture LANDED`
  section to `docs/plans/probe-runner-engine-capture-gaps.md` (mechanism; FORM_PROPS rationale;
  the querySelectorAll-targeting divergence + FS3 smear finding; FS5 combinator; content-free
  invariants; new code; ceilings incl. cursor deferral-break + shadow/iframe + radio-group;
  verification) and update the roadmap footer (P14 landed; remove form-state pseudo-classes from
  Remaining). Commit: `git add docs/plans/probe-runner-engine-capture-gaps.md && git commit -m "docs: record form-state capture (P14) landed"`.
- [ ] **A7: advisor done-gate**, then report DONE + await go-signal. Do NOT push. Do NOT
  auto-start the next rung.

---

## Self-Review (against the spec)

- **Spec coverage:** §1 scope → T4 constants (FORM_PROPS/SELECTORS) + branch; §2 mechanism → T4
  `capture_with_form_states`; §3 bundle → T2; §4 redactor → T1; §5 content-free → T3 (prose +
  cursor url() canaries) + gate on-disk checks; §6 tests/gates → T1-T5 + A1-A5; §7 ceilings →
  documented in code (capture docstring) + A6 docs. All covered.
- **Placeholder scan:** none — every code step shows full code; every run step shows the command +
  expected output.
- **Type consistency:** `redact_form_state` (T1) used by `apply_node_form_state` (T2);
  `_node_form_state` carrier produced in T4, popped in T2 `main`; `node_form_state` kwarg name
  identical in T2 signature/call; field name `form_state` consistent across T2/T3/T5;
  `FORM_PROPS`/`FORM_STATE_SELECTORS` names identical T4 code ↔ T4 tests ↔ gate.
- **Ordering note:** T2 (`main` pops `_node_form_state`) and T4 (capture produces it) are
  independent; either order works since `pop(..., {})` defaults safely when absent. T3 depends on
  nothing (firewall unchanged). Execute T1→T5 in order for clean commits.
