# Fixed-width `@container` capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an additive per-node `container` sidecar capturing the resolved-CSS restyle each element takes when its fixed-width inline-size `@container` query container is forced to representative absolute widths — the component-adaptive behavior Regime-3c misses for non-viewport-tracking containers.

**Architecture:** New `capture_with_container_queries` in `web_skeleton.py` (sibling to `capture_with_breakpoints`). It discovers query containers by computed `container-type`, then per container MUTATES the element's inline width (`Runtime.callFunctionOn`, save/restore — there is NO CDP primitive to emulate container size), snapshots over `CONTAINER_PROPS`, diffs vs a fixed-viewport base via the `_theme` pure core, and keys per-`(container,width)` into `_node_container`. `bundle_writer` attaches+redacts it; `content_firewall` is the unchanged backstop (verified by canary, not assumed); a host CDP gate proves the discover→mutate→revert path.

**Tech Stack:** Python 3, Chrome DevTools Protocol (DOMSnapshot / DOM.pushNodesByBackendIdsToFrontend / DOM.resolveNode / Runtime.callFunctionOn), pytest. Spec: `docs/plans/container-query-capture-design.md`. Probe: `research/capture-gap-probes/probe_container_query.py` (`b320ed1`).

---

## STANDING CONSTRAINTS (every task — verbatim-critical)

- **Commits SINGLE-LINE**, no trailers / no `Co-Authored-By` / no body.
- **Stage files EXPLICITLY by path** — NEVER `git add -A` / `git add .`.
- **ONE commit per task.** A review-driven fix gets its OWN commit.
- **Do NOT push.** All work local on `master`.
- **CDP host gate (T5) + real-site harness run on HOST Bash by the CONTROLLER** with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox). Implementer subagents WRITE the gate/harness files and STATIC-CHECK only: `python3 -c "import ast; ast.parse(open('<path>').read()); print('AST OK')"`. They do NOT run them.
- **Content firewall IP boundary:** never persist/print copyrighted/third-party content. Real-site validation prints/persists ONLY content-free signal (prop NAMES + COUNTS + host netloc; never values, resolved strings, selectors, or full URLs). Failure paths print returncode only — NEVER subprocess stderr.
- **`backendNodeId` (and transient CDP `nodeId`) are INTERNAL** — never on disk.
- All other unit tests run in-session via pytest (sandbox-safe; CDP is monkeypatched).

---

## File Structure

- `scripts/_style.py` — add `redact_container = redact_theme` alias (T1).
- `scripts/bundle_writer.py` — add `apply_node_container`, `assemble` param, `main` pop+thread (T2).
- `scripts/content_firewall.py` — NO change expected; T3 proves it via a canary.
- `scripts/web_skeleton.py` — add `CONTAINER_PROPS`, `DEFAULT_CONTAINER_WIDTHS`, `CONTAINER_BASE_VIEWPORT`, helper funcs, `capture_with_container_queries`, `--container-queries` flag + `main` branch (T4).
- `scripts/test_style.py`, `scripts/test_bundle_writer.py`, `scripts/test_content_firewall.py`, `scripts/test_web_skeleton.py` — tests per task.
- `fixtures/container-query/run_container_query.py` — host CDP gate (T5; controller-run).
- After-tasks (controller): `.gitignore`, `fixtures/container-query/validate_realsite.py`, docs.

---

## Task 1: `redact_container` redactor alias

**Files:**
- Modify: `scripts/_style.py` (after the `redact_form_state` alias, ~line 162)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_style.py` (and ensure the import line at top includes `redact_container`):

```python
from _style import redact_container  # add to the existing `from _style import ...` line


def test_redact_container_is_redact_theme_alias():
    from _style import redact_theme
    assert redact_container is redact_theme           # alias, not a wrapper (cannot drift)
    delta = {"0@240": {"display": "flex", "font-size": "11px"}}
    assert redact_container(delta) == delta           # passthrough on the flat shape
    assert redact_container(redact_container(delta)) == delta   # idempotent
    assert redact_container(None) is None             # None-safe (matches redact_theme)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_container_is_redact_theme_alias -v`
Expected: FAIL with `ImportError: cannot import name 'redact_container'`.

- [ ] **Step 3: Add the alias**

In `scripts/_style.py`, immediately after the `redact_form_state = redact_theme` alias block, add:

```python
# Fixed-width @container: the per-node delta is the flat {label:{prop:value}} theme shape
# (labels "<container_node_id>@<width>"), so its redactor is the SAME walker — an alias,
# exactly like redact_responsive / redact_reduced_motion / redact_form_state. @container is
# @media's size-threshold sibling, so values are CONTAINER_PROPS (== RESPONSIVE_PROPS) layout
# keywords / lengths / track-lists — no content/url — but the alias keeps firewall recursion +
# canary symmetry with theme. PASSTHROUGH redactor: the firewall is the SOLE backstop.
redact_container = redact_theme
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_style.py::test_redact_container_is_redact_theme_alias -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_container alias for @container delta sidecar"
```

---

## Task 2: `apply_node_container` bundle integration

**Files:**
- Modify: `scripts/bundle_writer.py` (add `apply_node_container` after `apply_node_form_state` ~line 252; extend `assemble` ~line 255; extend `main` ~line 358)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_bundle_writer.py`:

```python
def test_apply_node_container_attaches_redacted_delta():
    import bundle_writer as bw
    nodes = [{"id": 0}, {"id": 1}]
    node_container = {1: {"7@240": {"font-size": "11px", "display": "flex"}}}
    bw.apply_node_container(nodes, node_container)
    assert "container" not in nodes[0]                       # no entry -> no field
    assert nodes[1]["container"] == {"7@240": {"font-size": "11px", "display": "flex"}}


def test_apply_node_container_none_safe():
    import bundle_writer as bw
    nodes = [{"id": 0}]
    bw.apply_node_container(nodes, None)                     # must not raise
    bw.apply_node_container(nodes, {})                       # empty -> no-op
    assert "container" not in nodes[0]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_container_attaches_redacted_delta test_bundle_writer.py::test_apply_node_container_none_safe -v`
Expected: FAIL with `AttributeError: module 'bundle_writer' has no attribute 'apply_node_container'`.

- [ ] **Step 3: Implement `apply_node_container`**

In `scripts/bundle_writer.py`, immediately after `apply_node_form_state` (ends ~line 252), add:

```python
def apply_node_container(nodes, node_cq):
    """Attach each node's fixed-width @container restyle-delta map as node["container"],
    redacted by _style (redact_container is a redact_theme alias; CONTAINER_PROPS layout
    keywords/lengths/track-lists kept verbatim). node_cq: {node_id: {"<container_node_id>@
    <width>": {prop: value}}}. Runs BEFORE cf.redact_node, which preserves the `container`
    key (not a CONTENT_KEYS entry; redact_node filters only top-level keys). No entry / empty
    delta -> no field. Sibling to theme/pseudo_state/responsive/reduced_motion/form_state
    (same flat shape). A descendant under nested containers carries one label per swept
    (container, width) — the composite key keeps them distinct."""
    if not node_cq:
        return
    for n in nodes:
        cv = node_cq.get(n["id"])
        if cv:
            n["container"] = _style.redact_container(cv)
```

- [ ] **Step 4: Thread it through `assemble`**

In `scripts/bundle_writer.py`, change the `assemble` signature (~line 255-258) to add a trailing `node_container=None`:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None,
             node_responsive=None, node_keyframes=None, node_reduced_motion=None,
             node_form_state=None, node_container=None):
```

And add the call immediately after the existing `apply_node_form_state(nodes, node_form_state)` line (~line 272):

```python
    apply_node_container(nodes, node_container)
```

- [ ] **Step 5: Thread it through `main`**

In `scripts/bundle_writer.py` `main`, immediately after the `raw_form_state` / `node_form_state` pop (~line 358-359) and BEFORE `skeleton.pop("_node_backend", None)`:

```python
    raw_container = skeleton.pop("_node_container", {})
    node_container = {int(k): v for k, v in raw_container.items()}
```

Then extend the `assemble(...)` call (~line 367-374) to pass it — change the tail of the call to:

```python
                      node_reduced_motion=node_reduced_motion,
                      node_form_state=node_form_state,
                      node_container=node_container)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -v`
Expected: all PASS (the two new + the existing suite unregressed).

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: attach and redact per-node @container sidecar in bundle_writer"
```

---

## Task 3: Firewall canary (verify, do NOT assume)

**Files:**
- Modify: `scripts/test_content_firewall.py` (canary only)
- Modify (ONLY IF the canary fails): `scripts/content_firewall.py`

**Context:** `CONTAINER_PROPS == RESPONSIVE_PROPS` (layout keywords / lengths / grid track-lists — no url, no color). The one realistic prose vector is an author-named grid line (`grid-template-columns: [sidebar] 1fr`). The firewall's `_prose_in_json` walks EVERY nested string regardless of key (the leaf key here is a CSS prop name like `display`, not a `_PROSE_EXEMPT_KEYS` font key), so a 24+-char prose run in a `container` delta value SHOULD trip `kind=="prose"`. This task PROVES that with a canary rather than asserting it (the form-state rung taught that "firewall unchanged" must be proven). No firewall edit is expected.

- [ ] **Step 1: Write the canary test**

Add to `scripts/test_content_firewall.py`:

```python
def test_audit_canary_unredacted_prose_in_container_trips(tmp_path):
    import content_firewall as cf
    bundle = tmp_path / "b"
    bundle.mkdir()
    # A node whose `container` delta value smuggles unredacted prose (the failure mode:
    # if a redactor regressed to leak a content string into a @container delta). The flat
    # {label:{prop:value}} shape mirrors what apply_node_container emits.
    leak = "The quick brown fox jumped over the lazy dog repeatedly"   # > _PROSE 24-char floor
    skeleton = {"nodes": [{"id": 0, "role": "box",
                           "container": {"7@240": {"text-align": leak}}}]}
    (bundle / "skeleton.json").write_text(json.dumps(skeleton))
    viol = cf.audit_bundle(str(bundle))
    assert any(v["kind"] == "prose" for v in viol), \
        f"firewall failed to catch prose in a container delta: {viol}"
```

(Ensure `import json` is present at the top of the test file; it already is for the existing canaries.)

- [ ] **Step 2: Run the canary**

Run: `cd scripts && python3 -m pytest test_content_firewall.py::test_audit_canary_unredacted_prose_in_container_trips -v`
Expected: **PASS** (the firewall already catches nested prose regardless of key). 

- [ ] **Step 3: Branch on the result**

- **If Step 2 PASSED** (expected): no firewall change. Skip to Step 4.
- **If Step 2 FAILED** (unexpected — a real gap, like the form-state cursor canary): STOP, report the gap to the controller. The fix (broadening the firewall) is a SEPARATE commit with its own adversarial review, NOT folded into this task.

- [ ] **Step 4: Run the full firewall suite (regression)**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -v`
Expected: all PASS (new canary + existing suite green).

- [ ] **Step 5: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: canary proves firewall catches prose in @container deltas"
```

---

## Task 4: `capture_with_container_queries` + `--container-queries`

**Files:**
- Modify: `scripts/web_skeleton.py` (constants after `RESPONSIVE_PROPS`/`DEFAULT_BREAKPOINTS` ~line 104; helpers + `capture_with_container_queries` after `capture_with_form_states` ~line 982; flag ~line 1085; `main` branch after `args.form_states` ~line 1169)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_web_skeleton.py`:

```python
def test_container_props_and_widths_curated():
    import web_skeleton as W
    assert W.CONTAINER_PROPS == W.RESPONSIVE_PROPS         # @container == @media restyle vocab
    assert W.DEFAULT_CONTAINER_WIDTHS == "240,480,720"
    for p in ("width", "height", "margin-top", "padding-left"):
        assert p not in W.CONTAINER_PROPS                  # continuous-px excluded (anti-chimera)
    assert W.CONTAINER_BASE_VIEWPORT == 1440


def test_cq_container_backends_filters_inline_size():
    import web_skeleton as W
    base = {
        5: {"container-type": "inline-size"},
        6: {"container-type": "size"},          # 2D -> ceiling, skipped
        7: {"container-type": "normal"},        # not a container
        8: {},                                  # absent -> not a container
    }
    assert W._cq_container_backends(base) == [5]


def _cq_fake_ev(base_w=320):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                return {"nodeIds": [900 + b for b in params["backendNodeIds"]]}
            if method == "DOM.resolveNode":
                return {"object": {"objectId": "obj-%d" % params["nodeId"]}}
            if method == "Runtime.callFunctionOn":
                fn = params["functionDeclaration"]
                if "getBoundingClientRect" in fn:
                    return {"result": {"value": base_w}}
                if "getPropertyValue" in fn:      # SET width -> returns saved "value|priority"
                    return {"result": {"value": "|"}}
                return {}                          # RESTORE / other
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    return FakeEv()


def test_capture_with_container_queries_sweeps_keys_and_clamps(monkeypatch):
    import web_skeleton as W
    ev = _cq_fake_ev(base_w=320)
    # node 0 -> backend 5 (the inline-size container); node 1 -> backend 7 (its child)
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))
    # base snapshot, then one cond snapshot per swept width. base_w=320 so only 240 is < 320
    # (480/720 clamped). At 240 the child (backend 7) font-size moves 20 -> 11 (the @container
    # restyle); the container (backend 5) does not change a CONTAINER_PROPS value.
    snaps = iter([
        [  # base
            {"backend": 5, "pseudo": None, "style": {"container-type": "inline-size", "font-size": "16px"}},
            {"backend": 7, "pseudo": None, "style": {"font-size": "20px"}},
        ],
        [  # cond @240
            {"backend": 5, "pseudo": None, "style": {"container-type": "inline-size", "font-size": "16px"}},
            {"backend": 7, "pseudo": None, "style": {"font-size": "11px"}},
        ],
    ])
    monkeypatch.setattr(W, "_snapshot_recs", lambda ev, props=None: next(snaps))

    sk = W.capture_with_container_queries(ev, "chrome", "http://x", [240, 480, 720])

    # composite key "<container_node_id>@<width>" = "0@240"; delta on the child node id "1".
    assert sk["_node_container"] == {"1": {"0@240": {"font-size": "11px"}}}
    # clamp: only 240 was set (480/720 > base_w 320 are no-op widenings).
    set_calls = [p for (m, p) in ev.sess.sent
                 if m == "Runtime.callFunctionOn" and "getPropertyValue" in p["functionDeclaration"]]
    assert len(set_calls) == 1 and set_calls[0]["arguments"] == [{"value": "240px"}]
    # revert uses save/restore (setProperty/removeProperty) — NEVER removeAttribute.
    assert not any("removeAttribute" in p.get("functionDeclaration", "")
                   for (m, p) in ev.sess.sent if m == "Runtime.callFunctionOn")
    restore_calls = [p for (m, p) in ev.sess.sent
                     if m == "Runtime.callFunctionOn" and "indexOf('|')" in p["functionDeclaration"]]
    assert len(restore_calls) == 1                      # the one set width was reverted


def test_capture_with_container_queries_clears_forced_on_error(monkeypatch):
    import web_skeleton as W
    ev = _cq_fake_ev(base_w=320)
    node_backend = {0: 5}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, node_backend))
    calls = {"n": 0}
    def boom(ev, props=None):
        calls["n"] += 1
        if calls["n"] == 1:                              # base ok
            return [{"backend": 5, "pseudo": None, "style": {"container-type": "inline-size"}}]
        raise RuntimeError("snapshot boom")              # COND fails AFTER the width is set
    monkeypatch.setattr(W, "_snapshot_recs", boom)

    try:
        W.capture_with_container_queries(ev, "chrome", "http://x", [240])
    except RuntimeError:
        pass
    # finally must restore the forced width (a RESTORE callFunctionOn after the failure).
    restore_calls = [p for (m, p) in ev.sess.sent
                     if m == "Runtime.callFunctionOn" and "indexOf('|')" in p["functionDeclaration"]]
    assert restore_calls, "GATE FAIL: forced inline width not restored on error"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -k container_queries -v` and `... -k "container_props or cq_container_backends" -v`
Expected: FAIL with `AttributeError` (functions/constants not defined).

- [ ] **Step 3: Add constants**

In `scripts/web_skeleton.py`, immediately after the `RESPONSIVE_PROPS = [...]` and `DEFAULT_BREAKPOINTS = "390,768,1440"` block (~line 101-104), add:

```python
# Regime-3c follow-on: fixed-width @container. @container is @media's size-threshold sibling,
# so it reuses the SAME restyle vocab (width/height/margin/padding deliberately excluded —
# bbox carries rendered size; anti-chimera, and it drops the induced-mutation geometry).
CONTAINER_PROPS = RESPONSIVE_PROPS
DEFAULT_CONTAINER_WIDTHS = "240,480,720"   # representative narrow/medium component widths
CONTAINER_BASE_VIEWPORT = 1440             # fixed wide viewport during the sweep (container
#                                            size is governed by the forced inline width, not
#                                            the viewport — phantom-diff)
```

- [ ] **Step 4: Add the helpers + capture function**

In `scripts/web_skeleton.py`, immediately after `capture_with_form_states` (ends ~line 982) and BEFORE `def _capture_one`, add:

```python
# JS run via Runtime.callFunctionOn on a container's resolved object. _CQ_SET_WIDTH forces
# inline width !important (beats author width) and RETURNS the prior inline width as
# "value|priority" so the revert can restore it. _CQ_RESTORE_WIDTH consumes that string:
# removeProperty when there was no prior inline width, else setProperty(saved) — NEVER
# removeAttribute('style'), which would clobber a real element's author inline styles
# (advisor correctness blocker; the probe's removeAttribute masked this on a clean synthetic
# element). _CQ_BASE_WIDTH reads the natural rendered width for the W < base clamp.
_CQ_SET_WIDTH = ("function(w){var o=this.style.getPropertyValue('width');"
                 "var p=this.style.getPropertyPriority('width');"
                 "this.style.setProperty('width', w, 'important');return o+'|'+p;}")
_CQ_RESTORE_WIDTH = ("function(s){var i=s.indexOf('|');var o=s.slice(0,i);var p=s.slice(i+1);"
                     "if(o===''){this.style.removeProperty('width');}"
                     "else{this.style.setProperty('width', o, p);}}")
_CQ_BASE_WIDTH = "function(){return this.getBoundingClientRect().width;}"


def _cq_container_backends(base_styles):
    """backendNodeIds of inline-size query containers, from base resolved styles.
    container-type:size (2D) is a documented ceiling (page-root height artifacts, probe CQ7);
    normal / absent are not containers. Pure over the styles map -> unit-testable."""
    return [b for b, st in base_styles.items()
            if (st.get("container-type") or "normal") == "inline-size"]


def _cq_resolve_object(ev, backend):
    """container backendNodeId -> Runtime objectId via push->resolve. Returns None on miss
    (drop-on-miss ceiling, mirrors the capture_with_pseudo_states push-drop)."""
    pushed = ev.sess.send("DOM.pushNodesByBackendIdsToFrontend",
                          {"backendNodeIds": [backend]})
    ids = [nid for nid in (pushed.get("nodeIds") or []) if nid]
    if not ids:
        return None
    obj = ev.sess.send("DOM.resolveNode", {"nodeId": ids[0]})
    return (obj.get("object") or {}).get("objectId")


def _cq_call(ev, object_id, fn, args=()):
    """Runtime.callFunctionOn (returnByValue); returns the JS return value (or None)."""
    r = ev.sess.send("Runtime.callFunctionOn",
                     {"objectId": object_id, "functionDeclaration": fn,
                      "arguments": [{"value": a} for a in args], "returnByValue": True})
    return (r.get("result") or {}).get("value")


def capture_with_container_queries(ev, engine, url, widths, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton at a FIXED wide viewport, discover inline-size query
    containers by computed container-type, then for each container force its inline width to
    representative absolute widths (W < base, !important), recapture CONTAINER_PROPS, and diff
    vs base; attach per-(container,width) restyle deltas as the _node_container sidecar (keyed
    by node id; backendNodeId + CDP nodeId stay internal).

    The component-adaptive sweep Regime-3c misses: a FIXED-width container's size is
    independent of the viewport, so setDeviceMetricsOverride never re-triggers its @container
    rules. There is NO CDP primitive to emulate container size, so we MUTATE the container
    element's inline width (probe CQ2: backendNodeId survives the non-navigate mutation; CQ3:
    rules re-eval in the captured styles; CQ6: revert restores base). Each container's width is
    reverted via SAVE/RESTORE (never removeAttribute) so a real element's author inline styles
    survive and the next sweep diffs a clean base. Composite label '<container_node_id>@<W>'
    keeps a descendant's deltas distinct when it sits under nested containers (CQ5 transitive
    re-eval is recorded faithfully under the outer sweep). Base + every swept snapshot use
    SNAPSHOT_PROPS (phantom-diff); the diff universe is CONTAINER_PROPS only (container-type is
    read for discovery, never diffed). CDP-only; caller guards on hasattr(ev, "sess").

    Ceilings (design §7): container-type:size skipped (2D, page-root artifacts, CQ7);
    viewport-tracking inline-size containers are ALSO swept -> overlaps R3c (cannot distinguish
    from computed style; documented, no detect-exclude); push-resolve drop-on-miss; shadow/
    iframe not pierced; swept widths are off-render states (the sweep intent)."""
    snapshot_props = CONTAINER_PROPS + ["container-type"]
    sk, _layout, _page, node_backend = _capture_one(ev, engine, url,
                                                     width=CONTAINER_BASE_VIEWPORT,
                                                     max_wait=max_wait)
    base = _theme.styles_by_backend(_snapshot_recs(ev, snapshot_props))
    backend_to_id = {b: nid for nid, b in node_backend.items()}
    ev.sess.send("DOM.enable", {})
    ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})
    containers = _cq_container_backends(base)
    per_condition = {}
    forced = []   # (object_id, saved) still needing revert (exception safety)
    try:
        for cb in containers:
            object_id = _cq_resolve_object(ev, cb)
            cid = backend_to_id.get(cb)
            if object_id is None or cid is None:
                continue
            base_w = _cq_call(ev, object_id, _CQ_BASE_WIDTH) or 0
            for w in widths:
                if not (w < base_w):
                    continue                  # skip no-op widenings (clamp to W < base)
                saved = _cq_call(ev, object_id, _CQ_SET_WIDTH, ["%dpx" % int(w)])
                forced.append((object_id, saved))
                time.sleep(0.25)              # let reflow + @container re-eval settle
                cond = _theme.styles_by_backend(_snapshot_recs(ev, snapshot_props))
                delta = _theme.diff_theme(base, cond, CONTAINER_PROPS)
                per_condition["%d@%d" % (cid, int(w))] = \
                    _theme.rekey_by_node_id(delta, node_backend)
                _cq_call(ev, object_id, _CQ_RESTORE_WIDTH, [saved])   # revert -> clean base
                forced.pop()
        node_cq = _theme.build_node_theme(per_condition)
        sk["_node_container"] = {str(k): v for k, v in node_cq.items()}
        return sk
    finally:
        for object_id, saved in forced:       # exception mid-sweep -> restore author width
            try:
                _cq_call(ev, object_id, _CQ_RESTORE_WIDTH, [saved])
            except Exception:
                pass
```

- [ ] **Step 5: Add the `--container-queries` flag**

In `scripts/web_skeleton.py` `main`, immediately after the `--form-states` `add_argument` block (~line 1085, before `--max-wait`), add:

```python
    p.add_argument("--container-queries", nargs="?", const=DEFAULT_CONTAINER_WIDTHS,
                   default=None, dest="container_queries",
                   help="comma container widths e.g. 240,480,720 (bare --container-queries "
                        "uses the default 240,480,720); capture per-node resolved-style "
                        "restyle deltas as each fixed-width inline-size @container query "
                        "container is forced to those widths (DOM width mutation, "
                        "backendNodeId join) into the _node_container sidecar. Closes the R3c "
                        "fixed-width @container ceiling; DISTINCT from --breakpoints "
                        "(viewport-tracking containers only).")
```

- [ ] **Step 6: Add the `main` dispatch branch**

In `scripts/web_skeleton.py` `main`, immediately after the `elif args.form_states:` block (ends ~line 1169) and BEFORE `elif args.viewports:`, add:

```python
    elif args.container_queries:
        try:
            widths = [int(w) for w in args.container_queries.split(",") if w.strip()]
        except ValueError:
            die(f"web_skeleton --container-queries: widths must be integers, got "
                f"{args.container_queries!r} (e.g. --container-queries 240,480,720)")
        if not widths or any(w <= 0 for w in widths):
            die("web_skeleton --container-queries needs >=1 positive integer width "
                "(e.g. --container-queries 240,480,720)")
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --container-queries needs a CDP transport "
                    "(DOM.pushNodesByBackendIdsToFrontend / Runtime.callFunctionOn). "
                    "Use chrome host / --cdp-port.")
            out_obj = capture_with_container_queries(ev, engine, args.url, widths,
                                                     max_wait=args.max_wait)
        finally:
            ev.close()
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -v`
Expected: all PASS (the 4 new + existing suite unregressed).

- [ ] **Step 8: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: capture fixed-width @container restyle deltas via container width mutation"
```

---

## Task 5: Host CDP gate (controller-run)

**Files:**
- Create: `fixtures/container-query/run_container_query.py`

**Implementer:** write the file and STATIC-CHECK only (`python3 -c "import ast; ast.parse(open('fixtures/container-query/run_container_query.py').read()); print('AST OK')"`). Do NOT run it (CDP unreachable from the ctx sandbox). The CONTROLLER runs it on host Bash with `dangerouslyDisableSandbox=true`. This gate is the FIRST real test of the discover→push→resolve→mutate→revert path (the unit tests fake the CDP session).

- [ ] **Step 1: Write the gate**

Create `fixtures/container-query/run_container_query.py`:

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --container-queries discovers fixed-width inline-size @container
query containers by computed container-type, MUTATES each container's width to swept values,
captures the per-node restyle delta, and the pipeline redacts it content-free. PROVES, in one
deterministic offline run: (1) a fixed-width container's child re-evals @container at a swept
width that crosses its threshold but NOT at one that doesn't (per-width isolation); (2) a
NESTED container's child re-evals TRANSITIVELY when its ancestor shrinks AND when swept
directly — the composite '<container>@<width>' key keeps the two distinct; (3) a
container-type:size (2D) container is SKIPPED (its child gets no delta — documented ceiling);
(4) a non-container node gets NO delta; (5) backendNodeId / the carrier sidecar never reach
disk; (6) bundle_writer.write_bundle's firewall audit passes (RAISES on leak). Runs on host
CDP."""
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

# Fixed-width containers (independent of the viewport — the case R3c misses). box-sizing
# border-box so a child's bbox is stable for identification. Sweep widths "300,180":
#   #cqi (320, thresh 250):   @300 -> 300<320 swept but 300>250 NO fire (isolation);
#                             @180 -> 180<250 #cqc fires (11px) AND nested #cqi2 (=162<200)
#                             #cqc2 fires TRANSITIVELY under #cqi@180.
#   #cqi2 (90% => 288, thresh 200): @300 clamped (300>288); @180 -> 180<200 #cqc2 fires
#                             DIRECTLY under #cqi2@180 (distinct composite key).
#   #cqs (size, 200x100):     SKIPPED entirely (container-type:size ceiling) -> #cqsc no delta.
#   #plain:                   no container, no rule -> no delta.
_PAGE = """<!doctype html><meta charset=utf-8><title>cq-gate</title>
<style>
 * { box-sizing: border-box; }
 #cqi { container-type: inline-size; width: 320px; }
 #cqc { display:block; font-size:20px; width:100px; height:30px; }
 @container (max-width:250px){ #cqc { font-size:11px; } }
 #cqi2 { container-type: inline-size; width: 90%; }
 #cqc2 { font-size:16px; width:60px; height:20px; }
 @container (max-width:200px){ #cqc2 { font-size:8px; } }
 #cqs { container-type: size; width:200px; height:100px; }
 #cqsc { font-size:14px; width:40px; height:15px; }
 @container (max-height:50px){ #cqsc { font-size:7px; } }
 #plain { width:120px; height:44px; font-size:15px; }
</style>
<div id=cqi><div id=cqc>c</div><div id=cqi2><div id=cqc2>n</div></div></div>
<div id=cqs><div id=cqsc>s</div></div>
<div id=plain>p</div>"""

_SIZE = {"cqc": (100.0, 30.0), "cqc2": (60.0, 20.0),
         "cqsc": (40.0, 15.0), "plain": (120.0, 44.0)}
_SIZE_TOL = 2.5


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

    # On-disk regression locks: the internal carrier + join key must NEVER reach disk; the
    # per-node `container` field IS expected (that's the feature).
    assert "_node_container" not in sk, "GATE FAIL: internal carrier _node_container leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    # (1) #cqc: fires ONLY at the swept width that crosses its threshold (180), NOT at 300.
    cqc = _node_by_size(nodes, _SIZE["cqc"])
    assert cqc is not None and cqc.get("container"), "GATE FAIL: #cqc has no container delta"
    labels = list(cqc["container"].keys())
    assert len(labels) == 1 and labels[0].endswith("@180"), \
        f"GATE FAIL: #cqc should fire only @180, got {labels}"
    assert cqc["container"][labels[0]].get("font-size") == "11px", \
        f"GATE FAIL: #cqc @180 font-size wrong: {cqc['container'][labels[0]]}"

    # (2) #cqc2 (nested): TWO labels, both @180 (transitive via #cqi, direct via #cqi2),
    # distinct container node_ids -> composite key keeps them apart.
    cqc2 = _node_by_size(nodes, _SIZE["cqc2"])
    assert cqc2 is not None and cqc2.get("container"), "GATE FAIL: #cqc2 has no container delta"
    labs2 = list(cqc2["container"].keys())
    assert len(labs2) == 2, f"GATE FAIL: #cqc2 expected 2 composite labels (transitive+direct), got {labs2}"
    assert all(l.endswith("@180") for l in labs2), f"GATE FAIL: #cqc2 labels not both @180: {labs2}"
    assert len({l.split("@")[0] for l in labs2}) == 2, \
        f"GATE FAIL: #cqc2 two labels must have DISTINCT container ids: {labs2}"
    assert all(v.get("font-size") == "8px" for v in cqc2["container"].values()), \
        f"GATE FAIL: #cqc2 font-size delta wrong: {cqc2['container']}"

    # (3) #cqsc: parent is container-type:size -> SKIPPED -> no delta.
    cqsc = _node_by_size(nodes, _SIZE["cqsc"])
    assert cqsc is not None, "GATE FAIL: #cqsc node missing"
    assert not cqsc.get("container"), \
        f"GATE FAIL: #cqsc must have NO delta (size container skipped): {cqsc.get('container')}"

    # (4) #plain: no container, no rule -> isolation.
    plain = _node_by_size(nodes, _SIZE["plain"])
    assert plain is not None, "GATE FAIL: #plain node missing"
    assert not plain.get("container"), \
        f"GATE FAIL: #plain got a spurious container delta: {plain.get('container')}"

    print("GATE PASS: fixed-width @container join correct (#cqc fired ONLY @180 not @300; "
          "#cqc2 carries TWO distinct composite labels — transitive + direct nested re-eval; "
          "#cqs size-container SKIPPED; #plain isolated); backendNodeId never on disk; "
          "bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "container-query" / "_bundle"
    sk_json = ROOT / "fixtures" / "container-query" / "_sk.json"
    tok_json = ROOT / "fixtures" / "container-query" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--container-queries", "300,180", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Static-check the gate**

Run: `python3 -c "import ast; ast.parse(open('fixtures/container-query/run_container_query.py').read()); print('AST OK')"`
Expected: `AST OK`.

- [ ] **Step 3: Commit**

```bash
git add fixtures/container-query/run_container_query.py
git commit -m "test: add fixed-width @container host CDP gate"
```

> **Controller note (NOT an implementer step):** after T5 commits, the controller runs the gate on host Bash (`python3 fixtures/container-query/run_container_query.py`, `dangerouslyDisableSandbox=true`; add `--cdp-port 9222` to the web_skeleton subprocess only if a launch-mode connection fails). Expected: `GATE PASS`. If the gate's threshold/clamp arithmetic is off in practice (real Chrome layout), adjust the page sizes / sweep widths in a follow-up commit and re-run.

---

## After-Tasks (CONTROLLER, after all 5 tasks pass review)

1. **`.gitignore`** — add the gate runtime artifacts (own commit):
   ```
   fixtures/container-query/_sk.json
   fixtures/container-query/_tokens.json
   fixtures/container-query/_bundle/
   ```
   `git add .gitignore && git commit -m "chore: gitignore container-query gate runtime artifacts"`
2. **Run the host gate** (T5) on host CDP → expect `GATE PASS`.
3. **Run regression gates** — `fixtures/responsive`, `fixtures/form-state`, `fixtures/reduced-motion`, plus theme/pseudo-state/keyframes gates — confirm the shared `_capture_one`/`_snapshot_recs`/`_theme`/`bundle_writer` paths are unregressed.
4. **Full unit suite** — `cd scripts && python3 -m pytest -q` → all green (baseline + new).
5. **Real-site harness** — create `fixtures/container-query/validate_realsite.py` (content-free: host netloc, total nodes, nodes-with-`container`, per-(container,width) counts, changed-prop NAMES sorted, delta-size distribution, on-disk gate, audit result; failure prints returncode ONLY, never subprocess stderr). Run against a container-query-using site (e.g. a modern component-library docs page). Own commit.
6. **Docs** — add a `## §C9-R-P15 — Results: fixed-width @container LANDED` section to `docs/plans/probe-runner-engine-capture-gaps.md`; update the roadmap footer (move fixed-width @container from Remaining to landed); flip the `@container` row in `docs/research/css-capture-completeness.md` to note fixed-width now captured. Own commit.
7. **Final whole-feature review** — dispatch a final code reviewer over the full commit range.
8. **Advisor done-gate** — call advisor before declaring done. Report DONE, await go-signal. Do NOT push. Do NOT auto-start the next rung.

---

## Self-Review (writing-plans checklist)

**1. Spec coverage:** §2 mechanism → T4; §3 bundle → T2; §4 redactor → T1; §5 firewall → T3 (canary); §6 props/widths → T4 constants + `test_container_props_and_widths_curated`; §7 ceilings → T4 docstring + T5 gate (size skip, overlap) ; §9 tests → T1-T5 + after-tasks. No gap.

**2. Placeholder scan:** every code step has complete code; commands have expected output; no TBD/TODO/"similar to".

**3. Type/name consistency:** `redact_container` (T1) used by `apply_node_container` (T2); `_node_container` carrier popped in `bundle_writer.main` (T2) matches `sk["_node_container"]` set in `capture_with_container_queries` (T4); composite label `"%d@%d" % (cid, int(w))` (T4) matches the `endswith("@180")` / `split("@")[0]` gate assertions (T5) and the test `"0@240"` (T4 test); `CONTAINER_PROPS`/`DEFAULT_CONTAINER_WIDTHS`/`CONTAINER_BASE_VIEWPORT` defined T4 step 3, asserted T4 step 1; `_cq_container_backends`/`_cq_resolve_object`/`_cq_call`/`_CQ_SET_WIDTH`/`_CQ_RESTORE_WIDTH`/`_CQ_BASE_WIDTH` all defined T4 step 4 and referenced consistently.
