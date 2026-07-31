# Regime-4a CSS @keyframes Timeline Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture, as an additive per-node `keyframes` sidecar, the time-driven CSS `@keyframes` animation timeline each element references — keyframe offsets + animated-property values + timing — content-free, joined by `backendNodeId`.

**Architecture:** A pure parse core (`_keyframes.py`, mirroring `_theme.py`) turns CDP `CSS.getMatchedStylesForNode.cssKeyframesRules` + the node's computed `animation-*` into `[{timing, frames}]`, dropping the author `@keyframes` name (the timeline binds to the node). `web_skeleton --keyframes` does one navigate, reads `animation-*` per node via the 3c-generalized `_snapshot_recs(ev, props)`, selects candidates (`animation-name != none`), pushes their `backendNodeId`→frontend nodeId (R3b plumbing), queries matched keyframes, and attaches a `_node_keyframes` sidecar. Threaded through `bundle_writer` exactly like `responsive`/`theme`/`pseudo_state`; redacted by a NEW `_style.redact_keyframes` walker (the `[{timing,frames}]` shape differs from the flat `{label:{prop}}` redactors, so it is NOT an alias); `content_firewall.py` is UNCHANGED.

**Tech Stack:** Python 3, CDP (`CSS.getMatchedStylesForNode` / `DOM.pushNodesByBackendIdsToFrontend` / `DOMSnapshot.captureSnapshot`), pytest. Host CDP gate runs on host Bash (CDP unreachable from the ctx sandbox).

**Design spec:** `docs/plans/regime4a-keyframes-capture-design.md` (probe facts PR1–PR7 in §1; the controller has run and deleted that probe).

---

## File structure (what this plan creates / modifies)

- **Create** `scripts/_keyframes.py` — pure parse core: `parse_keyframes` + `_offset_from_keytext` + `_frames_from_rule` (T2).
- **Create** `scripts/test_keyframes.py` — unit tests for the pure core (T2).
- **Modify** `scripts/_style.py` — append `redact_keyframes` walker (T1).
- **Modify** `scripts/test_style.py` — `redact_keyframes` tests (T1).
- **Modify** `scripts/web_skeleton.py` — `ANIM_CANDIDATE_PROPS` + `ANIMATABLE_PROPS` constants; `capture_with_keyframes`; `--keyframes` flag + branch (T5).
- **Modify** `scripts/test_web_skeleton.py` — constants shape test; `capture_with_keyframes` orchestration tests (T5).
- **Modify** `scripts/bundle_writer.py` — `apply_node_keyframes`; `assemble(..., node_keyframes=None)`; `main` pops `_node_keyframes` (T3).
- **Modify** `scripts/test_bundle_writer.py` — `apply_node_keyframes` round-trip + None-safe (T3).
- **Modify** `scripts/test_content_firewall.py` — prose canary into `keyframes` (T4). `content_firewall.py` UNCHANGED.
- **Create** `fixtures/keyframes/run_keyframes.py` — host CDP gate (T6, controller-run).
- **Create** `fixtures/keyframes/validate_realsite.py` — content-free real-site harness (after-task, controller-run).

**Commit discipline (standing constraints — non-negotiable):** single-line commit messages, NO trailers / NO `Co-Authored-By` / NO body. Stage files EXPLICITLY by path; NEVER `git add -A`/`git add .`. ONE commit per task; a review-driven fix gets its OWN commit. Do NOT push. `backendNodeId` / CDP `nodeId` / `@keyframes` NAME NEVER on disk. Implementer subagents write gate/harness files + static-check only (`python3 -c "import ast; ast.parse(open(...).read())"`); the CONTROLLER runs the CDP gate (T6) and all after-tasks.

---

### Task 1: `redact_keyframes` walker

**Files:**
- Modify: `scripts/_style.py` (after line 148, `redact_responsive = redact_theme`)
- Test: `scripts/test_style.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_style.py`, extend the import block (after line 7) and add tests:

```python
from _style import redact_keyframes  # noqa: E402
```

```python
def test_redact_keyframes_keeps_timing_and_layout_redacts_url():
    anims = [{"timing": {"duration": "2s", "easing": "linear", "iterations": "infinite",
                         "direction": "normal", "delay": "0s", "fill": "none"},
              "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                         {"offset": 1.0, "props": {"transform": "rotate(360deg)",
                                                   "filter": 'url("https://a/b.svg#x")'}}]}]
    out = redact_keyframes(anims)
    assert out[0]["timing"]["iterations"] == "infinite"        # timing kept verbatim
    assert out[0]["frames"][0]["offset"] == 0.0                # offset kept
    assert out[0]["frames"][0]["props"]["transform"] == "rotate(0deg)"   # layout value kept
    assert out[0]["frames"][1]["props"]["filter"] == 'url("<asset>")'    # external url redacted


def test_redact_keyframes_is_not_redact_theme_alias_and_none_safe():
    # Distinct SHAPE ([{timing,frames}] vs flat {label:{prop}}) => its own walker, not an alias.
    assert redact_keyframes is not redact_theme
    assert redact_keyframes(None) is None
    assert redact_keyframes([]) == []
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py::test_redact_keyframes_keeps_timing_and_layout_redacts_url -q`
Expected: FAIL — `ImportError: cannot import name 'redact_keyframes'`.

- [ ] **Step 3: Add the walker**

In `scripts/_style.py`, after the `redact_responsive = redact_theme` line (line 148) and its comment block, append:

```python
def redact_keyframes(anims):
    """Redact one node's CSS @keyframes timeline list — shape
    [{timing: {...}, frames: [{offset: float, props: {prop: raw value}}]}]. timing
    values are content-free enums/numbers (kept verbatim); each frame prop value routes
    through redact_style_value (external/data url() -> url("<asset>"); same-doc
    url(#frag)/gradients/raw colors kept) via redact_node_styles. NOT an alias of
    redact_theme: the [{timing,frames}] shape differs from the flat {label:{prop:value}}
    theme/pseudo_state/responsive shape, so it needs its own walker. None/empty-safe;
    idempotent. The @keyframes NAME is never present here (dropped at capture)."""
    if not anims:
        return anims
    out = []
    for a in anims:
        frames = [{"offset": fr.get("offset"),
                   "props": redact_node_styles(fr.get("props"))}
                  for fr in a.get("frames", [])]
        out.append({"timing": a.get("timing"), "frames": frames})
    return out
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_style.py -q`
Expected: PASS (all, including the two new).

- [ ] **Step 5: Commit**

```bash
git add scripts/_style.py scripts/test_style.py
git commit -m "feat: add redact_keyframes walker for Regime-4a timelines"
```

---

### Task 2: `_keyframes.py` pure parse core

**Files:**
- Create: `scripts/_keyframes.py`
- Test: `scripts/test_keyframes.py`

- [ ] **Step 1: Write the failing tests**

Create `scripts/test_keyframes.py`:

```python
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))  # noqa: E402
import _keyframes as kf  # noqa: E402

ANIMATABLE = ["transform", "opacity", "filter", "color", "background-color",
              "border-color", "box-shadow", "translate", "rotate", "scale"]


def _rule(name, frames):
    # frames: list of (keyText, [(prop, value), ...])
    return {"animationName": {"text": name},
            "keyframes": [{"keyText": kt,
                           "style": {"cssProperties": [{"name": p, "value": v}
                                                       for p, v in props]}}
                          for kt, props in frames]}


def test_offset_from_keytext_percents_and_from_to():
    assert kf._offset_from_keytext("0%") == [0.0]
    assert kf._offset_from_keytext("50%") == [0.5]
    assert kf._offset_from_keytext("100%") == [1.0]
    assert kf._offset_from_keytext("from") == [0.0]
    assert kf._offset_from_keytext("to") == [1.0]
    assert kf._offset_from_keytext("0%, 100%") == [0.0, 1.0]   # comma list -> per offset
    assert kf._offset_from_keytext("garbage") == []


def test_parse_keyframes_single_animation_offsets_props_and_timing():
    rules = [_rule("spin", [("0%", [("transform", "rotate(0deg)")]),
                            ("100%", [("transform", "rotate(360deg)")])])]
    anim = {"animation-name": "spin", "animation-duration": "2s",
            "animation-timing-function": "linear", "animation-iteration-count": "infinite",
            "animation-direction": "normal", "animation-delay": "0s",
            "animation-fill-mode": "none"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert len(out) == 1
    assert out[0]["timing"] == {"duration": "2s", "easing": "linear",
                                "iterations": "infinite", "direction": "normal",
                                "delay": "0s", "fill": "none"}
    assert out[0]["frames"] == [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                                {"offset": 1.0, "props": {"transform": "rotate(360deg)"}}]
    assert "animationName" not in str(out)   # author name dropped


def test_parse_keyframes_dedups_longhand_shorthand_and_filters_whitelist():
    # probe PR3: props arrive duplicated; non-animatable props must be filtered out.
    rules = [_rule("p", [("50%", [("transform", "scale(1.2)"), ("transform", "scale(1.2)"),
                                  ("opacity", "0.4"), ("width", "10px")])])]
    anim = {"animation-name": "p", "animation-duration": "3s"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert out[0]["frames"] == [{"offset": 0.5,
                                 "props": {"transform": "scale(1.2)", "opacity": "0.4"}}]
    # width (not animatable) excluded; duplicate transform collapsed


def test_parse_keyframes_multi_animation_name_matched_pairing():
    # two animations; rules in REVERSE order -> must pair by name (transiently), timing
    # positionally by the animation-name list order, then drop the name.
    rules = [_rule("pulse", [("0%", [("opacity", "1")])]),
             _rule("spin", [("0%", [("transform", "rotate(0deg)")])])]
    anim = {"animation-name": "spin, pulse", "animation-duration": "2s, 3s",
            "animation-timing-function": "linear, ease"}
    out = kf.parse_keyframes(rules, anim, ANIMATABLE)
    assert len(out) == 2
    assert out[0]["frames"][0]["props"] == {"transform": "rotate(0deg)"}  # spin first
    assert out[0]["timing"]["duration"] == "2s" and out[0]["timing"]["easing"] == "linear"
    assert out[1]["frames"][0]["props"] == {"opacity": "1"}               # pulse second
    assert out[1]["timing"]["duration"] == "3s" and out[1]["timing"]["easing"] == "ease"


def test_parse_keyframes_drop_on_miss_and_empty():
    # animation-name references a @keyframes with no matching rule -> dropped.
    assert kf.parse_keyframes([], {"animation-name": "ghost"}, ANIMATABLE) == []
    # animation-name none -> nothing.
    assert kf.parse_keyframes([_rule("x", [("0%", [("opacity", "1")])])],
                              {"animation-name": "none"}, ANIMATABLE) == []
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_keyframes.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_keyframes'`.

- [ ] **Step 3: Write `_keyframes.py`**

Create `scripts/_keyframes.py`:

```python
#!/usr/bin/env python3
"""_keyframes — pure core for Regime-4a CSS @keyframes timeline capture (no browser,
no I/O). web_skeleton.capture_with_keyframes feeds it CDP
CSS.getMatchedStylesForNode.cssKeyframesRules + the node's computed animation-* dict; it
returns a content-free [{timing, frames}] list. The author @keyframes NAME is used only
TRANSIENTLY to pair each rule with its animation-name slot (for correct timing), then
DROPPED — never returned, never persisted. Deterministic; unit-tested. Mirrors _theme.py
as a pure, browser-free core."""


def _offset_from_keytext(keytext):
    """'0%'->[0.0], '50%'->[0.5], '100%'->[1.0], 'from'->[0.0], 'to'->[1.0]. A comma
    keyText ('0%, 100%') -> one offset per selector ([0.0, 1.0]). Unparseable tokens are
    skipped; an all-unparseable keyText -> []."""
    out = []
    for tok in (keytext or "").split(","):
        t = tok.strip().lower()
        if t == "from":
            out.append(0.0)
        elif t == "to":
            out.append(1.0)
        elif t.endswith("%"):
            try:
                out.append(round(float(t[:-1]) / 100.0, 6))
            except ValueError:
                pass
    return out


def _frames_from_rule(kf_rule, animatable):
    """One cssKeyframesRule -> offset-sorted [{offset, props}] over the `animatable`
    whitelist. Dedups duplicate prop names (probe PR3: longhand+shorthand expansion emits
    the prop twice). Explodes a comma keyText into one frame per offset. A frame with no
    offset or no animatable prop is skipped (drop the internal source `range`)."""
    frames = []
    for f in kf_rule.get("keyframes", []):
        offsets = _offset_from_keytext(f.get("keyText", ""))
        props = {}
        for p in f.get("style", {}).get("cssProperties", []):
            name = p.get("name")
            if name in animatable and name not in props:
                props[name] = p.get("value")
        if not offsets or not props:
            continue
        for off in offsets:
            frames.append({"offset": off, "props": dict(props)})
    frames.sort(key=lambda fr: fr["offset"])
    return frames


def _split_list(val):
    """Split a computed animation-* comma-list value into trimmed parts ([] when empty)."""
    return [s.strip() for s in val.split(",")] if val else []


def parse_keyframes(css_keyframes_rules, anim, animatable):
    """Build a node's content-free keyframes list.

    css_keyframes_rules: CSS.getMatchedStylesForNode(...)['cssKeyframesRules'].
    anim: the node's computed animation-* dict (animation-name + the six timing props).
    animatable: the ANIMATABLE_PROPS whitelist.

    Returns [{timing: {duration, easing, iterations, direction, delay, fill},
              frames: [{offset, props}]}], ordered by the node's animation-name list.
    Each entry's frames come from the cssKeyframesRule whose animationName matches that
    name (matched TRANSIENTLY, then dropped); timing is paired positionally from the
    comma-lists with CSS list-repetition (a list shorter than animation-name repeats via
    modulo). A name with no matching rule, or whose rule yields no animatable frames, is
    dropped (drop-on-miss). animation-name 'none'/'' -> []."""
    names = [n for n in _split_list(anim.get("animation-name")) if n and n != "none"]
    if not names:
        return []
    by_name = {}
    for r in css_keyframes_rules or []:
        nm = (r.get("animationName") or {}).get("text")
        if nm is not None and nm not in by_name:
            by_name[nm] = r
    durs = _split_list(anim.get("animation-duration"))
    eas = _split_list(anim.get("animation-timing-function"))
    its = _split_list(anim.get("animation-iteration-count"))
    dirs = _split_list(anim.get("animation-direction"))
    dels = _split_list(anim.get("animation-delay"))
    fils = _split_list(anim.get("animation-fill-mode"))

    def pick(lst, i, default):
        return lst[i % len(lst)] if lst else default

    out = []
    for i, nm in enumerate(names):
        rule = by_name.get(nm)
        if rule is None:
            continue
        frames = _frames_from_rule(rule, animatable)
        if not frames:
            continue
        out.append({"timing": {"duration": pick(durs, i, "0s"),
                               "easing": pick(eas, i, "ease"),
                               "iterations": pick(its, i, "1"),
                               "direction": pick(dirs, i, "normal"),
                               "delay": pick(dels, i, "0s"),
                               "fill": pick(fils, i, "none")},
                    "frames": frames})
    return out
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_keyframes.py -q`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add scripts/_keyframes.py scripts/test_keyframes.py
git commit -m "feat: add _keyframes pure parse core for Regime-4a"
```

---

### Task 3: `apply_node_keyframes` + bundle threading

**Files:**
- Modify: `scripts/bundle_writer.py` (`apply_node_responsive` ends ~line 207; `assemble` line 209; `main` pops ~line 297)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing tests**

In `scripts/test_bundle_writer.py` (module imported as `bw`), add after the `test_apply_node_responsive_*` tests:

```python
def test_apply_node_keyframes_attaches_redacted_timeline():
    nodes = [{"id": 0}, {"id": 1}]
    node_kf = {0: [{"timing": {"duration": "2s", "easing": "linear",
                               "iterations": "infinite", "direction": "normal",
                               "delay": "0s", "fill": "none"},
                    "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                               {"offset": 1.0, "props": {"filter": 'url("https://a/b.svg")'}}]}]}
    bw.apply_node_keyframes(nodes, node_kf)
    assert nodes[0]["keyframes"][0]["timing"]["iterations"] == "infinite"
    assert nodes[0]["keyframes"][0]["frames"][0]["props"]["transform"] == "rotate(0deg)"
    assert nodes[0]["keyframes"][0]["frames"][1]["props"]["filter"] == 'url("<asset>")'
    assert "keyframes" not in nodes[1]            # no entry -> no field


def test_apply_node_keyframes_none_safe():
    nodes = [{"id": 0}]
    bw.apply_node_keyframes(nodes, None)
    bw.apply_node_keyframes(nodes, {})
    assert "keyframes" not in nodes[0]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py::test_apply_node_keyframes_attaches_redacted_timeline -q`
Expected: FAIL — `AttributeError: module 'bundle_writer' has no attribute 'apply_node_keyframes'`.

- [ ] **Step 3: Add `apply_node_keyframes`**

In `scripts/bundle_writer.py`, immediately after `apply_node_responsive` (ends ~line 207) and before `def assemble`, add:

```python
def apply_node_keyframes(nodes, node_kf):
    """Attach each node's CSS @keyframes timeline list as node["keyframes"], redacted by
    _style (frame prop values: external/data url() -> url("<asset>"); timing + offsets
    kept verbatim). node_kf: {node_id: [{timing, frames}]}. Runs BEFORE cf.redact_node,
    which preserves the `keyframes` key (not a CONTENT_KEYS entry). No entry / empty list
    -> no field. DISTINCT from the scroll/interaction motion model (match_motion) and from
    the per-node theme/pseudo_state/responsive deltas — this is the time-driven CSS
    animation curve (the @keyframes NAME is never present; dropped at capture)."""
    if not node_kf:
        return
    for n in nodes:
        kv = node_kf.get(n["id"])
        if kv:
            n["keyframes"] = _style.redact_keyframes(kv)
```

- [ ] **Step 4: Thread through `assemble`**

Change the `assemble` signature (lines 209–211) to add a trailing `node_keyframes=None`:

```python
def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None,
             node_responsive=None, node_keyframes=None):
```

Inside `assemble`, immediately after the existing `apply_node_responsive(nodes, node_responsive)` line, add:

```python
    apply_node_keyframes(nodes, node_keyframes)
```

(Order: ...→ node_responsive → node_keyframes → `motion = match_motion(...)` → `cf.redact_node`. Match the existing indentation.)

- [ ] **Step 5: Thread through `main`**

In `scripts/bundle_writer.py` `main`, after the `raw_responsive`/`node_responsive` lines (297–298) and BEFORE `skeleton.pop("_node_backend", None)` (line 299), add:

```python
    raw_keyframes = skeleton.pop("_node_keyframes", {})
    node_keyframes = {int(k): v for k, v in raw_keyframes.items()}
```

Then extend the `assemble(...)` call (the final kwargs, ~line 311) — add `node_keyframes=node_keyframes`:

```python
                      node_responsive=node_responsive, node_keyframes=node_keyframes)
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_bundle_writer.py -q`
Expected: PASS (all, including the two new). The default-None addition must not break any existing assemble/round-trip test.

- [ ] **Step 7: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: thread CSS keyframes timelines through bundle assemble"
```

---

### Task 4: Firewall prose canary into `keyframes`

**Files:**
- Modify: `scripts/test_content_firewall.py`
- `scripts/content_firewall.py` — **UNCHANGED** (no new content vector; `audit_bundle`'s key-aware walk already recurses arbitrary nested dicts/lists).

- [ ] **Step 1: Write the failing test**

In `scripts/test_content_firewall.py` (module imported as `cf`, helper `_clean_bundle`), add (mirror the `responsive` canary):

```python
def test_audit_canary_unredacted_prose_in_keyframes_trips(tmp_path):
    # Structural proof that audit_bundle's key-aware walker recurses into
    # node["keyframes"][i]["frames"][j]["props"][prop] (through a LIST, not just dicts):
    # an un-redacted PROSE leak under a frame prop trips ONLY via the key-aware prose walk
    # (the flat _CONTENT_URL/_DATA_URI/_B64_BLOB detectors do NOT match plain prose). If
    # redact_keyframes ever failed to redact a content value, THIS is the backstop. Mirrors
    # the theme/pseudo_state/responsive prose canaries.
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "keyframes": [{"timing": {"duration": "2s"},
                                    "frames": [{"offset": 0.0,
                                                "props": {"transform":
                                                          "This is leaked prose content here now"}}]}]}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    viol = cf.audit_bundle(d)
    assert viol, "un-redacted prose in a keyframes frame must trip the audit"
    assert any(v.get("kind") == "prose" for v in viol), \
        "must trip via the key-aware prose walk (proves keyframes/list recursion), not a flat detector"
```

- [ ] **Step 2: Run to verify it passes immediately**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_content_firewall.py::test_audit_canary_unredacted_prose_in_keyframes_trips -q`
Expected: **PASS without touching `content_firewall.py`** — the canary asserts the EXISTING key-aware walker already reaches `node.keyframes[i].frames[j].props[prop]` (recursing through the `keyframes` LIST). (TDD inversion: it confirms an existing invariant holds for the new key+list nesting. If it FAILS — e.g. the walker does not descend into lists — STOP and escalate; do NOT modify `content_firewall.py`.)

- [ ] **Step 3: Run the full firewall suite**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: add firewall prose canary for keyframes timelines"
```

---

### Task 5: `capture_with_keyframes` + `--keyframes` flag

**Files:**
- Modify: `scripts/web_skeleton.py` (constants after `DEFAULT_BREAKPOINTS` line 103; new function after `capture_with_breakpoints` ~line 808; argparse + branch in `main`)
- Test: `scripts/test_web_skeleton.py`

**Model:** integration/judgment task (multi-step CDP orchestration) — dispatch with a capable model (opus).

- [ ] **Step 1: Write the failing tests**

In `scripts/test_web_skeleton.py` (module imported as `ws`), add:

```python
def test_animatable_and_candidate_props_curated():
    for p in ("transform", "opacity", "filter", "color", "background-color",
              "border-color", "box-shadow", "translate", "rotate", "scale"):
        assert p in ws.ANIMATABLE_PROPS
    for p in ("width", "height", "margin-top", "top"):
        assert p not in ws.ANIMATABLE_PROPS          # layout-thrash excluded (anti-bloat)
    assert "animation-name" in ws.ANIM_CANDIDATE_PROPS
    for p in ("animation-duration", "animation-timing-function", "animation-iteration-count",
              "animation-direction", "animation-delay", "animation-fill-mode"):
        assert p in ws.ANIM_CANDIDATE_PROPS


def test_capture_with_keyframes_selects_candidates_pushes_parses(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params):
            self.sent.append((method, params))
            if method == "DOM.pushNodesByBackendIdsToFrontend":
                # frontend nodeIds positionally aligned to the input backendNodeIds
                return {"nodeIds": [900 + b for b in params["backendNodeIds"]]}
            if method == "CSS.getMatchedStylesForNode":
                # the pushed node for backend 5 (frontend 905) animates 'spin'
                if params["nodeId"] == 905:
                    return {"cssKeyframesRules": [
                        {"animationName": {"text": "spin"},
                         "keyframes": [
                             {"keyText": "0%", "style": {"cssProperties": [
                                 {"name": "transform", "value": "rotate(0deg)"}]}},
                             {"keyText": "100%", "style": {"cssProperties": [
                                 {"name": "transform", "value": "rotate(360deg)"}]}}]}]}
                return {"cssKeyframesRules": []}
            return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    # node 0 -> backend 5 animates; node 1 -> backend 7 has no animation
    node_backend = {0: 5, 1: 7}
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}, {"id": 1}]}, None, None, node_backend))
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [
            {"backend": 5, "pseudo": None, "style": {"animation-name": "spin",
                "animation-duration": "2s", "animation-timing-function": "linear",
                "animation-iteration-count": "infinite", "animation-direction": "normal",
                "animation-delay": "0s", "animation-fill-mode": "none"}},
            {"backend": 7, "pseudo": None, "style": {"animation-name": "none"}}])

    sk = W.capture_with_keyframes(ev, "chrome", "http://x")

    # only the animating node gets a keyframes entry; keyed by node id (string); name dropped.
    assert sk["_node_keyframes"] == {"0": [
        {"timing": {"duration": "2s", "easing": "linear", "iterations": "infinite",
                    "direction": "normal", "delay": "0s", "fill": "none"},
         "frames": [{"offset": 0.0, "props": {"transform": "rotate(0deg)"}},
                    {"offset": 1.0, "props": {"transform": "rotate(360deg)"}}]}]}
    assert "1" not in sk["_node_keyframes"]
    pushed = [p for (m, p) in ev.sess.sent if m == "DOM.pushNodesByBackendIdsToFrontend"]
    assert pushed and pushed[0]["backendNodeIds"] == [5]   # only the candidate pushed (not 7)
    assert "spin" not in str(sk["_node_keyframes"])        # @keyframes name never in output


def test_capture_with_keyframes_no_candidates_empty_sidecar(monkeypatch):
    import web_skeleton as W

    class FakeSess:
        def __init__(self): self.sent = []
        def send(self, method, params): self.sent.append((method, params)); return {}

    class FakeEv:
        def __init__(self): self.sess = FakeSess()
        def ev(self, expr): return None
        def close(self): pass

    ev = FakeEv()
    monkeypatch.setattr(W, "_capture_one",
        lambda ev, engine, url, width=None, max_wait=None:
            ({"nodes": [{"id": 0}]}, None, None, {0: 5}))
    monkeypatch.setattr(W, "_snapshot_recs",
        lambda ev, props=None: [{"backend": 5, "pseudo": None,
                                 "style": {"animation-name": "none"}}])
    sk = W.capture_with_keyframes(ev, "chrome", "http://x")
    assert sk["_node_keyframes"] == {}
    # no candidates -> no push at all
    assert not any(m == "DOM.pushNodesByBackendIdsToFrontend" for (m, p) in ev.sess.sent)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_keyframes_selects_candidates_pushes_parses -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'capture_with_keyframes'` (and `ANIMATABLE_PROPS` missing).

- [ ] **Step 3: Add the constants**

In `scripts/web_skeleton.py`, after the `DEFAULT_BREAKPOINTS = "390,768,1440"` line (line 103) and its block, add:

```python
# Regime-4a: CSS @keyframes timeline capture. ANIM_CANDIDATE_PROPS = the computed
# animation-* props read per node to (a) SELECT candidates (animation-name != none) and
# (b) source content-free timing; animation-name is used TRANSIENTLY to pair rules and is
# NEVER persisted. ANIMATABLE_PROPS = the curated content-free props @keyframes typically
# drive (layout-thrash props excluded — bbox carries size; design §2.1). Frames are read
# from CSS.getMatchedStylesForNode.cssKeyframesRules (authored path — covers finished/
# not-started/running, unlike getAnimations; probe PR1/PR2).
ANIM_CANDIDATE_PROPS = ["animation-name", "animation-duration",
                        "animation-timing-function", "animation-iteration-count",
                        "animation-direction", "animation-delay", "animation-fill-mode"]
ANIMATABLE_PROPS = ["transform", "opacity", "filter", "color", "background-color",
                    "border-color", "box-shadow", "translate", "rotate", "scale"]
```

Confirm `_keyframes` is imported at the top of `web_skeleton.py` (alongside `_theme`); if not, add `import _keyframes` next to the existing `import _theme`.

- [ ] **Step 4: Add `capture_with_keyframes`**

In `scripts/web_skeleton.py`, after `capture_with_breakpoints` (ends ~line 808) and before `def _capture_one`, add:

```python
def capture_with_keyframes(ev, engine, url, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton, then attach each animating node's CSS @keyframes
    timeline as the _node_keyframes sidecar (keyed by node id; backendNodeId + the
    @keyframes NAME stay internal/dropped). One navigate, no Emulation override.

    Candidates = nodes whose computed animation-name != none (read via the 3c-generalized
    _snapshot_recs(ev, ANIM_CANDIDATE_PROPS)). Their backendNodeIds are pushed to frontend
    nodeIds in one DOM.pushNodesByBackendIdsToFrontend call (R3b plumbing; nodeIds come
    back positionally aligned to the input). Per candidate, CSS.getMatchedStylesForNode
    returns cssKeyframesRules for exactly that node's referenced @keyframes regardless of
    play state (probe PR2 — covers finished one-shots getAnimations misses); _keyframes
    parses them into [{timing, frames}] over ANIMATABLE_PROPS, dropping the name.

    CDP-only (the caller guards on hasattr(ev, "sess")). Ceiling (design §6): authored
    keyframe values leave var()/calc() unresolved; a candidate whose getMatchedStylesForNode
    yields no animatable frames is dropped (drop-on-miss)."""
    sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
    anim_by_backend = _theme.styles_by_backend(_snapshot_recs(ev, ANIM_CANDIDATE_PROPS))
    cand_backends = [b for b, st in anim_by_backend.items()
                     if (st.get("animation-name") or "none").strip() not in ("none", "")]
    if not cand_backends:
        sk["_node_keyframes"] = {}
        return sk
    ev.sess.send("DOM.enable", {})
    ev.sess.send("CSS.enable", {})
    ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})
    pushed = ev.sess.send("DOM.pushNodesByBackendIdsToFrontend",
                          {"backendNodeIds": cand_backends})
    node_ids = pushed.get("nodeIds") or []
    backend_to_id = {b: nid for nid, b in node_backend.items()}
    by_node = {}
    for backend, front in zip(cand_backends, node_ids):
        if not front:
            continue
        ms = ev.sess.send("CSS.getMatchedStylesForNode", {"nodeId": front})
        anims = _keyframes.parse_keyframes(ms.get("cssKeyframesRules") or [],
                                           anim_by_backend.get(backend, {}),
                                           ANIMATABLE_PROPS)
        if not anims:
            continue
        nid = backend_to_id.get(backend)
        if nid is not None:
            by_node[nid] = anims
    sk["_node_keyframes"] = {str(k): v for k, v in by_node.items()}
    return sk
```

- [ ] **Step 5: Run the orchestration tests**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -m pytest test_web_skeleton.py::test_capture_with_keyframes_selects_candidates_pushes_parses test_web_skeleton.py::test_capture_with_keyframes_no_candidates_empty_sidecar test_web_skeleton.py::test_animatable_and_candidate_props_curated -q`
Expected: PASS all three.

- [ ] **Step 6: Add the `--keyframes` flag + branch**

In `scripts/web_skeleton.py` `main`, register the flag immediately after the `--breakpoints` argument (line 887–893, before `--max-wait`):

```python
    p.add_argument("--keyframes", action="store_true", default=False,
                   help="capture per-node CSS @keyframes animation timelines "
                        "(CSS.getMatchedStylesForNode, backendNodeId join) into the "
                        "_node_keyframes sidecar. Content-free: keyframe offsets + "
                        "animated-property values + timing; the @keyframes NAME is never "
                        "persisted. Authored-path (covers finished/not-started anims).")
```

Add the handler branch AFTER the `elif args.breakpoints:` block (ends ~line 949) and BEFORE `elif args.viewports:` (line 950):

```python
    elif args.keyframes:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --keyframes needs a CDP transport "
                    "(CSS.getMatchedStylesForNode). Use chrome host / --cdp-port.")
            out_obj = capture_with_keyframes(ev, engine, args.url, max_wait=args.max_wait)
        finally:
            ev.close()
```

Note: `--keyframes` joins the existing mutually-exclusive `if/elif` chain (first-match-wins, consistent with the landed pattern). Confirm the branch assigns to `out_obj` (the variable the post-chain write step consumes — same as the sibling branches).

- [ ] **Step 7: Static-check + full suite**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Then `python3 -m pytest test_web_skeleton.py -q` → PASS (full file; the live CLI branch is exercised end-to-end by the host gate in Task 6, which only the controller runs).

- [ ] **Step 8: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: add capture_with_keyframes and --keyframes flag"
```

---

### Task 6: Host CDP gate (controller-run)

**Files:**
- Create: `fixtures/keyframes/run_keyframes.py`

**Implementer:** write the file and static-check it (`python3 -c "import ast; ast.parse(...)"`). Do NOT run it (CDP unreachable from the ctx sandbox). The CONTROLLER runs it on host Bash with `dangerouslyDisableSandbox=true`.

- [ ] **Step 1: Write the gate**

Create `fixtures/keyframes/run_keyframes.py`:

```python
#!/usr/bin/env python3
"""Host gate: web_skeleton --keyframes captures per-node CSS @keyframes timelines via
CSS.getMatchedStylesForNode (authored path), and the pipeline redacts them content-free.
PROVES: an INFINITE anim (#spin) + a multi-stop anim (#pulse) are captured with correct
offsets/props; a FINISHED fill:none one-shot (#oneshot, absent from getAnimations) IS
captured (the authored-path coverage win, probe PR2); a NOT-YET-STARTED long-delay anim
(#delayed) IS captured; a node with NO animation (#static) gets NO keyframes field
(isolation); and the @keyframes NAME ('spin'/'pulse') NEVER reaches disk. Deterministic,
offline (local server). bundle_writer.write_bundle runs the firewall audit and RAISES on
leak."""
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

# Fixed px sizes so nodes are identifiable by bbox. #oneshot finishes (~0.3s, fill:none)
# and #delayed never starts (5s delay) within the capture window — both MUST still be
# captured because cssKeyframesRules is keyed off the computed animation-name (set in
# every play state), unlike getAnimations.
_PAGE = """<!doctype html><meta charset=utf-8><title>kf-gate</title>
<style>
 @keyframes spin { from { transform: rotate(0deg);} to { transform: rotate(360deg);} }
 @keyframes pulse { 0% { opacity:1; transform:scale(1);} 50% { opacity:.4; transform:scale(1.2);} 100% { opacity:1; transform:scale(1);} }
 #spin    { animation: spin 2s linear infinite; width:40px; height:40px; }
 #pulse   { animation: pulse 3s ease-in-out infinite; width:50px; height:50px; }
 #oneshot { animation: spin 0.3s linear 1; width:20px; height:20px; }
 #delayed { animation: spin 2s linear 5s 1; width:30px; height:30px; }
 #static  { width:80px; height:40px; }
</style>
<div id=spin></div><div id=pulse></div><div id=oneshot></div>
<div id=delayed></div><div id=static></div>"""

_SIZE = {"spin": (40.0, 40.0), "pulse": (50.0, 50.0), "oneshot": (20.0, 20.0),
         "delayed": (30.0, 30.0), "static": (80.0, 40.0)}
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


def _offsets(kf_entry):
    return [round(fr.get("offset"), 3) for fr in kf_entry["frames"]]


def _check(bundle_dir):
    raw = (Path(bundle_dir) / "skeleton.json").read_text()
    sk = json.loads(raw)
    nodes = sk.get("nodes") or []

    assert "_node_keyframes" not in sk, "GATE FAIL: internal carrier _node_keyframes leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"
    # the @keyframes author NAME must never reach disk (the core content-free invariant).
    assert "spin" not in raw and "pulse" not in raw, \
        "GATE FAIL: @keyframes author name leaked into the on-disk skeleton"

    spin = _node_by_size(nodes, _SIZE["spin"])
    assert spin is not None and spin.get("keyframes"), "GATE FAIL: #spin has no keyframes"
    a = spin["keyframes"][0]
    assert _offsets(a) == [0.0, 1.0], f"GATE FAIL: #spin offsets wrong: {_offsets(a)}"
    assert "transform" in a["frames"][0]["props"], f"GATE FAIL: #spin missing transform: {a['frames'][0]}"
    assert a["timing"]["iterations"] == "infinite", f"GATE FAIL: #spin iterations wrong: {a['timing']}"

    pulse = _node_by_size(nodes, _SIZE["pulse"])
    assert pulse is not None and pulse.get("keyframes"), "GATE FAIL: #pulse has no keyframes"
    pa = pulse["keyframes"][0]
    assert _offsets(pa) == [0.0, 0.5, 1.0], f"GATE FAIL: #pulse offsets wrong: {_offsets(pa)}"
    assert "opacity" in pa["frames"][1]["props"], f"GATE FAIL: #pulse @50% missing opacity: {pa['frames'][1]}"

    oneshot = _node_by_size(nodes, _SIZE["oneshot"])
    assert oneshot is not None and oneshot.get("keyframes"), \
        "GATE FAIL: #oneshot (finished fill:none) not captured — authored-path coverage broken (probe PR2)"

    delayed = _node_by_size(nodes, _SIZE["delayed"])
    assert delayed is not None and delayed.get("keyframes"), \
        "GATE FAIL: #delayed (not-yet-started) not captured — authored-path coverage broken"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("keyframes"), \
        f"GATE FAIL: #static got a spurious keyframes field (isolation): {static.get('keyframes')}"

    print("GATE PASS: keyframes capture correct (#spin offsets [0,1]+transform+infinite; "
          "#pulse offsets [0,0.5,1]+opacity; #oneshot finished one-shot CAPTURED; #delayed "
          "not-started CAPTURED; #static isolated — no field); @keyframes name never on "
          "disk; backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "keyframes" / "_bundle"
    sk_json = ROOT / "fixtures" / "keyframes" / "_sk.json"
    tok_json = ROOT / "fixtures" / "keyframes" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--keyframes", "--out", str(sk_json)],
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

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 -c "import ast; ast.parse(open('fixtures/keyframes/run_keyframes.py').read()); print('parse-ok')"`
Expected: `parse-ok`. Implementer does NOT execute the gate.

- [ ] **Step 3: Commit (implementer)**

```bash
git add fixtures/keyframes/run_keyframes.py
git commit -m "test: add Regime-4a keyframes host gate fixture"
```

- [ ] **Step 4: CONTROLLER runs the gate on host**

Controller only (host Bash, `dangerouslyDisableSandbox=true`):
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/keyframes/run_keyframes.py`
Expected: `GATE PASS: ...`. If `#oneshot`/`#delayed` asserts fail, the authored-path coverage premise is broken (contradicts probe PR2) — STOP and escalate. If the `"spin"/"pulse" not in raw` assert fails, the @keyframes name is leaking — STOP (content-free invariant breach); the parse must be dropping the name (`_keyframes.parse_keyframes`) and `capture_with_keyframes` must not stash it — fix in its OWN commit, re-run.

---

## After-tasks (CONTROLLER only — run after Task 6 gate PASS)

These are NOT plan tasks; the controller executes them directly (host Bash for CDP).

1. **Regime-3a/3b/3c gate regression** (R4a adds a `_snapshot_recs(ev, ANIM_CANDIDATE_PROPS)` call but does NOT modify `_snapshot_recs`; still re-run the shared-path gates to prove no regression):
   `python3 fixtures/theme/run_theme.py`, `python3 fixtures/pseudo-state/run_pseudo_state.py`, `python3 fixtures/responsive/run_responsive.py` → each `GATE PASS`.
2. **Full unit suite:** `cd scripts && python3 -m pytest -q` → all green (375 baseline + new T1/T2/T3/T4/T5 tests).
3. **Real-site validation harness** — create `fixtures/keyframes/validate_realsite.py` (content-free: prints ONLY host netloc + count of nodes-with-keyframes + the SET of animatable-prop NAMES seen + counts; NO content / resolved values / full URL / @keyframes names; `bundle_writer` raising = caught leak). Mirror `fixtures/responsive/validate_realsite.py` structure. Commit (`test: add Regime-4a content-free real-site validation harness`). Controller runs it against ≥1 public site with CSS animation; audit must be CLEAN; report content-free signal only.
4. **Docs** — add `§C9-R-P12 — Regime-4a CSS @keyframes capture LANDED` to `docs/plans/probe-runner-engine-capture-gaps.md` and update its roadmap-status footer (P12 landed; in Remaining, replace the "Regime-4 authored-rule/keyframe parse" entry with "Regime-4b authored cascade [blocked on matched-vs-inactive content-free wall]"). Commit (`docs: record Regime-4a keyframes capture (P12) landed`).
5. **Final code review** — dispatch a final reviewer subagent over the whole commit range; fix any Critical/Important in its OWN commit.
6. **Advisor done-gate**, then report DONE and await the go signal for the next rung (R4b brainstorm, or another rung). Do NOT push. Do NOT auto-start the next rung.

---

## Self-Review

**1. Spec coverage:** §1 probe PR1–PR7 → premise behind T5 (gate T6 re-proves PR2 via #oneshot/#delayed). §2.1 ANIMATABLE_PROPS → T5 constant + shape test. §2.2 ANIM_CANDIDATE_PROPS / candidate-select / transient name → T5. §2.3 sidecar shape `[{timing,frames}]` → T2 (parse) + T3 (bundle) + T5 (capture). §3 capture flow (base via `_capture_one`, candidate read via `_snapshot_recs(ev, ANIM_CANDIDATE_PROPS)`, push, getMatchedStylesForNode, parse, no override) → T5. §4 backendNodeId join, never on disk; name dropped → T2 (drop name) + T5 (push/rekey) + T6 on-disk locks (incl. name-absence grep). §5 reuse + NEW redact_keyframes/apply_node_keyframes/parse → T1/T2/T3/T5. §6 ceilings (var/calc unresolved — documented in T5 docstring; drop-on-miss — T2 + T5; multi-anim positional pairing — T2 test) . §7 bundle + firewall UNCHANGED → T3 + T4. §8 testing → T1–T6 + after-tasks. §9 CLI `--keyframes` → T5.

**2. Placeholder scan:** none — every code step carries complete code; the only described-not-coded item is the real-site harness (after-task), which references `fixtures/responsive/validate_realsite.py` as the exact pattern to mirror (not a plan task).

**3. Type/name consistency:** `ANIM_CANDIDATE_PROPS` (list), `ANIMATABLE_PROPS` (list), `_keyframes.parse_keyframes(css_keyframes_rules, anim, animatable)`, `_offset_from_keytext`, `_frames_from_rule`, `redact_keyframes(anims)` (genuine walker, asserted `is not redact_theme`), `apply_node_keyframes(nodes, node_kf)`, `assemble(..., node_keyframes=None)`, `capture_with_keyframes(ev, engine, url, max_wait=...)`, `_node_keyframes` (sidecar key), `keyframes` (per-node field), `--keyframes` flag — names identical across every task. Sidecar values keyed by `str(node_id)`; `main` re-keys via `int(k)` (matches the theme/pseudo_state/responsive pop pattern). The per-node entry shape `{timing:{duration,easing,iterations,direction,delay,fill}, frames:[{offset,props}]}` is identical in T2 parse output, T3 apply tests, T5 orchestration assert, and T6 gate asserts.
