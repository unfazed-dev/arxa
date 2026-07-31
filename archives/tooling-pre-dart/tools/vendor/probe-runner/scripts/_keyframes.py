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
        kt = f.get("keyText")
        if isinstance(kt, dict):        # real CDP CSSKeyframeRule.keyText is a Value {text, range}
            kt = kt.get("text", "")
        offsets = _offset_from_keytext(kt or "")
        props = {}
        for p in f.get("style", {}).get("cssProperties", []):
            name = p.get("name")
            val = p.get("value")
            if name in animatable and name not in props and val is not None:
                props[name] = val
        if not offsets or not props:
            continue
        for off in offsets:
            frames.append({"offset": off, "props": dict(props)})
    frames.sort(key=lambda fr: fr["offset"])
    return frames


def _split_list(val):
    """Split a computed animation-* comma-list into trimmed parts, respecting parenthesis
    depth so commas inside cubic-bezier(...)/steps(...) are NOT split (multi-animation
    animation-timing-function correctness — the one timing prop whose values contain
    commas). [] when empty."""
    if not val:
        return []
    parts, cur, depth = [], [], 0
    for ch in val:
        if ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth = max(0, depth - 1)
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur).strip())
    return parts


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
