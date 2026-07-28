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
    m = _CB.fullmatch(s)
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
        if beziers:   # candidates resolved, all to the linear identity -> genuinely linear
            return {"klass": "linear", "bezier": [0, 0, 1, 1], "certified": True, "reason": None}
        if parsed:    # candidates existed but none resolved -> unrecognized easing function
            return {"klass": "unknown", "bezier": None, "certified": False,
                    "reason": "unknown-easing"}
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
        nb = n.get("bbox")
        if not nb:
            continue
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
    unbound but bezier-representable law is still exact).
    Binding caveat: the anchor bbox is read mid-animation (the live window) while
    component nodes come from the settled snapshot, so for a large/slow TRANSFORM reveal
    the live box may sit more than `radius` from its own settled node — binding to None
    ("unbound") or, if a different settled node (e.g. a sibling) is nearer, MISATTRIBUTING
    to it. Binding is best-effort and proximity-based, not identity-verified.
    """
    if not anims_raw or not component:
        return None
    anims = []
    for a in anims_raw:
        if a.get("iterations") is None:   # JSON-null == non-finite == ambient loop
            continue
        dur = a.get("duration")
        if not dur or dur <= 0:           # zero/None duration == no real motion
            continue
        props = sorted(set(a.get("props") or []))
        if not props:                     # no nameable animated property -> nothing to reproduce
            continue
        easing = map_easing(a.get("easing"), a.get("kfEasings"))
        node = _bind_node(a.get("bbox"), component, radius)
        reason = easing["reason"]
        if reason is None and node is None:
            reason = "unbound"
        anims.append({
            "node": node,
            "props": props,
            "duration_ms": dur,
            "delay_ms": a.get("delay", 0) or 0,
            "easing": {"klass": easing["klass"], "bezier": easing["bezier"]},
            "certified": easing["certified"],
            "reason": reason,
        })
    if not anims:
        return None
    return {"n_anims": len(anims), "anims": anims}
