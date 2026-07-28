#!/usr/bin/env python3
"""web_skeleton — capture a content-independent design skeleton (role + REST
bbox + font metrics + z-order + sizing-behavior + auto-layout + parent tree) of
any URL via one CDP DOMSnapshot.captureSnapshot. Pure parse/classify/derive
funcs are unit-tested; the CDP capture in main() is live-validated."""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path

from _common import die, emit_json
from _web_eval import add_transport_args, navigate, resolve_web_eval, DEFAULT_MAX_WAIT
from _substrate import classify_substrate
import _theme
import _keyframes

# spec §4: tight base whitelist PLUS sizing-behavior inputs. Order is the
# contract — layout.styles[i] rows are parallel to this list.
WANT_STYLES = [
    "font-size", "font-weight", "line-height", "letter-spacing",
    "font-family", "text-align", "color", "background-color",
    "background-image", "border-top-width", "border-top-color", "border-radius",
    "opacity", "display", "visibility", "position", "z-index", "transform",
    # sizing-behavior inputs (spec §4):
    "flex-direction", "flex-grow", "flex-shrink", "flex-basis",
    "align-self", "align-items", "justify-content", "gap",
    "padding-top", "padding-right", "padding-bottom", "padding-left",
    "grid-template-columns", "grid-template-rows",
    "width", "height", "min-width", "max-width", "box-sizing",
    # Regime-1 visual-style props (cut 1). APPENDED — keeps every existing index
    # stable. Captured RAW (incl url()); redacted at packaging (_style/bundle_writer).
    "filter", "backdrop-filter",
    "clip-path", "box-shadow", "mix-blend-mode", "transform-origin",
    "border-right-width", "border-bottom-width", "border-left-width",
    "border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
    "border-right-color", "border-bottom-color", "border-left-color",
    "border-top-left-radius", "border-top-right-radius",
    "border-bottom-right-radius", "border-bottom-left-radius",
    # Regime-1 visual-style props (cut 2). APPENDED — keeps every existing index
    # stable (parallel-index contract). All 27 validated against captureSnapshot
    # (host probe 2026-05-31). Captured RAW; no new url() vector (redaction unchanged).
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
    # Regime-2: pseudo-element generated content. APPENDED (parallel-index contract —
    # keeps every existing index stable). Resolved RAW (literal text / counter() /
    # url()); redacted at packaging (_style.redact_content_value). NOT added to
    # STYLE_PROPS — real elements resolve content->normal; only pseudo rows
    # (::before/::after/::marker) carry a meaningful value.
    "content",
]

# Per-node visual-style props emitted onto node["style"] (Regime-1 cut 1). bg/fg and
# border-top-color stay in the _node_colors sidecar (palette token_ref) and are NOT
# duplicated here. transform-origin is handled separately (only when a transform is set).
STYLE_PROPS = [
    "filter", "backdrop-filter",
    "background-image", "clip-path", "box-shadow", "mix-blend-mode",
    "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
    "border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
    "border-right-color", "border-bottom-color", "border-left-color",
    "border-top-left-radius", "border-top-right-radius",
    "border-bottom-right-radius", "border-bottom-left-radius",
    # cut 2 (gating/defaults applied in _collect_style):
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
]

# Regime-3a: theme/preference diff. THEME_PROPS = the Regime-1 visual prop set +
# the three colors the _node_colors model holds (a subset of WANT_STYLES, so every
# value is present in a record's raw `style`). Geometry/sizing props are excluded —
# theme conditions restyle via color/effect, not box metrics; a display:none toggle
# is handled by drop-on-miss, not by diffing `display`.
THEME_PROPS = STYLE_PROPS + ["color", "background-color", "border-top-color"]

# Regime-3b: forced interactive pseudo-class states. The diff universe is THEME_PROPS
# verbatim (already covers color/background-color/box-shadow/outline-*/text-decoration-line —
# host probe F1/F1b confirmed; `cursor` deferred). Forced via CSS.forcePseudoState; the
# forcedPseudoClasses value is the bare name (no colon).
PSEUDO_STATES = ("hover", "focus", "active")

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

# Regime-3c follow-on: fixed-width @container. @container is @media's size-threshold sibling,
# so it reuses the SAME restyle vocab (width/height/margin/padding deliberately excluded —
# bbox carries rendered size; anti-chimera, and it drops the induced-mutation geometry).
CONTAINER_PROPS = RESPONSIVE_PROPS
DEFAULT_CONTAINER_WIDTHS = "240,480,720"   # representative narrow/medium component widths
CONTAINER_BASE_VIEWPORT = 1440             # fixed wide viewport during the sweep (container
#                                            size is governed by the forced inline width, not
#                                            the viewport — phantom-diff)

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

# Reduced-motion (P13): computed-prop delta under emulated prefers-reduced-motion:reduce.
# MOTION_PROPS = the props measured (probe PR2) to MOVE under reduce — animation off,
# transition off, smooth-scroll off. animation-play-state EXCLUDED (PR3: it does not move
# when animation is turned off, so it carries no signal). NOT a subset of WANT_STYLES, so
# it is snapshotted explicitly (the capture_with_breakpoints pattern).
MOTION_PROPS = ["animation-name", "animation-duration", "animation-iteration-count",
                "transition-duration", "transition-property", "scroll-behavior"]

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

# Pinned DEFAULT media for the base capture (design §3) — do NOT rely on ambient
# OS/headless defaults, or the delta becomes environment-dependent.
BASE_FEATURES = [
    {"name": "prefers-color-scheme", "value": "light"},
    {"name": "forced-colors", "value": "none"},
    {"name": "prefers-contrast", "value": "no-preference"},
]
# Each condition flips EXACTLY ONE feature off the pinned base (single-axis delta).
CONDITION_OVERRIDE = {
    "dark": {"name": "prefers-color-scheme", "value": "dark"},
    "forced-colors": {"name": "forced-colors", "value": "active"},
    "contrast": {"name": "prefers-contrast", "value": "more"},
}


def _condition_features(label):
    """BASE_FEATURES with the single feature for `label` overridden."""
    ov = CONDITION_OVERRIDE[label]
    return [ov if f["name"] == ov["name"] else f for f in BASE_FEATURES]


_STYLE_NOOP = {None, "", "none", "normal", "auto"}
# Cut-2 props whose Chrome RESOLVED DEFAULT is NOT in _STYLE_NOOP (host probe
# 2026-05-31). A prop is dropped when its resolved value equals its default — keeps
# the sidecar sparse (no default-valued prop lands on every node). Values are the
# verbatim probe output; default sets are lower-cased for comparison.
_STYLE_DEFAULTS = {
    "background-position": {"0% 0%"},
    "background-repeat": {"repeat"},
    "background-clip": {"border-box"},
    "background-origin": {"padding-box"},
    "background-attachment": {"scroll"},
    "overflow-x": {"visible"},
    "overflow-y": {"visible"},
    "object-fit": {"fill"},
    "object-position": {"50% 50%"},
    "writing-mode": {"horizontal-tb"},
    "direction": {"ltr"},
    "transform-style": {"flat"},
}
# Outline metrics/color resolve to NON-suppressible defaults on every node
# (outline-width:1.5px, outline-color:rgb(0,0,0), outline-offset:0px), so they are
# emitted ONLY when outline-style is set — gated, like transform-origin on transform.
_OUTLINE_GATED = ("outline-width", "outline-color", "outline-offset")


def _collect_style(st):
    """Sparse per-node visual style from resolved CSS. Emits a prop only when it has
    visual effect. Drop layers: a prop with a _STYLE_DEFAULTS entry is judged ONLY by
    that map (its real default may be a non-noop keyword like overflow:visible /
    object-fit:fill, and a noop-LOOKING value like overflow:auto / object-fit:none is
    MEANINGFUL — so the universal noop must NOT pre-empt the map); every other prop uses
    the universal noop set + the zero -width/-radius rule. Two gated groups:
    transform-origin only when `transform` is set; the outline metrics/color
    (_OUTLINE_GATED) only when `outline-style` is set. Values are RAW (url() redacted
    later at packaging). {} when nothing set."""
    out = {}
    for p in STYLE_PROPS:
        v = st.get(p)
        if v is None:
            continue
        s = v.strip().lower() if isinstance(v, str) else None
        if s == "":
            continue
        dflt = _STYLE_DEFAULTS.get(p)
        if dflt is not None:
            if s is not None and s in dflt:
                continue
        else:
            if s is not None and s in _STYLE_NOOP:
                continue
            if p.endswith(("-width", "-radius")) and (_px(v) or 0.0) == 0.0:
                continue
        out[p] = v
    tr = st.get("transform")
    if tr and tr.strip().lower() not in ("none", ""):
        to = st.get("transform-origin")
        if to and to.strip():
            out["transform-origin"] = to
    o_style = st.get("outline-style")
    if not (o_style and o_style.strip().lower() not in _STYLE_NOOP):
        for k in _OUTLINE_GATED:
            out.pop(k, None)
    return out


_PSEUDO_SELECTORS = {"before", "after", "marker"}


def _collect_pseudo(st, parent_color):
    """Sparse style for a pseudo-element (::before/::after/::marker) from its
    resolved style row. Reuses _collect_style for the cut-1/cut-2 box props, then
    adds the fg/bg/border-top-color the _node_colors model excludes (here inline as
    resolved rgb(), content-free) and the redaction-deferred `content`:
      - color (fg) ONLY when it differs from the originating element's resolved color
        (parent_color) — color inherits, so a default ::marker matches its list's text
        color and must NOT land on every <li>;
      - background-color when not transparent; border-top-color gated on border-top-style;
      - content (RAW; redacted at packaging) when not none/normal/empty.
    Geometry (the pseudo's bbox/size) is NOT captured (deferred). {} when nothing set."""
    out = _collect_style(st)
    bg = st.get("background-color")
    if bg is not None and bg.strip().lower() not in _TRANSPARENT:
        out["background-color"] = bg
    bts = st.get("border-top-style")
    if bts and bts.strip().lower() not in _STYLE_NOOP:
        btc = st.get("border-top-color")
        if btc and btc.strip():
            out["border-top-color"] = btc
    color = st.get("color")
    if color and color.strip() and color != parent_color:
        out["color"] = color
    content = st.get("content")
    if content is not None and content.strip().lower() not in ("none", "normal", ""):
        out["content"] = content
    return out


def parse_snapshot(snap, want_styles, dpr=1.0):
    """Flatten a DOMSnapshot into skeleton records.

    DOMSnapshot.captureSnapshot returns layout bounds in DEVICE pixels, but the
    rest of the bundle (page/viewport dims, web_anim motion anchors, tokens) is
    in CSS pixels. We divide bounds by `dpr` so every coordinate in the skeleton
    is CSS px and match_motion can join CSS-px anchors to skeleton nodes. dpr=1
    (default, and the non-retina / deviceScaleFactor:1 path) is a no-op.
    """
    strings = snap["strings"]
    inv_dpr = 1.0 / dpr if dpr else 1.0

    def s(idx):
        return strings[idx] if idx is not None and idx >= 0 else None

    out = []
    for doc in snap["documents"]:
        nodes = doc["nodes"]
        layout = doc["layout"]
        names = nodes["nodeName"]
        li_node = layout["nodeIndex"]
        bounds = layout["bounds"]
        styles = layout["styles"]
        ltext = layout.get("text", [])
        paints = layout.get("paintOrders", [])
        # contentDocumentIndex is doc-local, node-indexed sparse data: its `index`
        # entries are the node indices of frame owners whose document WAS captured
        # in this snapshot. A frame node NOT in this set was not captured
        # (out-of-process / cross-site OOPIF) -> opaque substrate (G11). Default to
        # empty when absent (legacy/synthetic snapshots have no frames).
        captured_frames = set((nodes.get("contentDocumentIndex") or {}).get("index", []) or [])
        # Regime-2: pseudoType is sparse RareStringData ({index:[node_idx],
        # value:[strIdx]}). Map node index -> pseudo kind ("before"/"after"/"marker")
        # so each record can carry r["pseudo"]; None for real elements.
        pt = nodes.get("pseudoType") or {}
        pseudo_by_node = {idx: s(val)
                          for idx, val in zip(pt.get("index", []), pt.get("value", []))}
        backend = nodes.get("backendNodeId") or []
        attributes = nodes.get("attributes") or []

        def _href_of(node_idx):
            row = attributes[node_idx] if node_idx < len(attributes) else []
            for k in range(0, len(row) - 1, 2):
                if s(row[k]) == "href":
                    return s(row[k + 1])
            return None

        for i, dom_i in enumerate(li_node):
            x, y, w, h = bounds[i]
            x, y, w, h = x * inv_dpr, y * inv_dpr, w * inv_dpr, h * inv_dpr
            # Real CDP emits variable-length style rows: rendered nodes carry one
            # string-index per want_style, but document/non-rendered nodes carry an
            # empty row. Guard the per-column lookup so a short row yields None.
            srow = styles[i] if i < len(styles) else []
            tag = (s(names[dom_i]) or "").upper()
            out.append({
                "dom_index": dom_i,
                "tag": tag,
                "bbox": {"x": round(x, 2), "y": round(y, 2),
                         "w": round(w, 2), "h": round(h, 2)},
                "z": paints[i] if i < len(paints) else 0,
                "style": {want_styles[k]: (s(srow[k]) if k < len(srow) else None)
                          for k in range(len(want_styles))},
                "text": s(ltext[i]) if i < len(ltext) else None,
                "substrate": classify_substrate(tag, captured=(dom_i in captured_frames)),
                "pseudo": pseudo_by_node.get(dom_i),
                "backend": backend[dom_i] if dom_i < len(backend) else None,
                "href": _href_of(dom_i) if tag == "A" else None,
            })
    return out


IMG_TAGS = {"IMG", "PICTURE", "VIDEO", "CANVAS", "SOURCE"}
_TRANSPARENT = {None, "", "transparent", "rgba(0, 0, 0, 0)", "rgba(0,0,0,0)"}


def svg_descendants(doc, strings):
    """Set of dom indexes that are an <svg> or live inside one."""
    nodes = doc["nodes"]
    names = nodes["nodeName"]
    parent = nodes["parentIndex"]
    out = set()
    n = len(names)
    for i in range(n):
        j = i
        while j is not None and j >= 0:
            name = strings[names[j]] if names[j] >= 0 else ""
            if (name or "").lower() == "svg":
                out.add(i)
                break
            j = parent[j]
    return out


def classify(rec, in_svg):
    b = rec["bbox"]
    if b["w"] <= 0 or b["h"] <= 0:
        return None
    tag = rec["tag"]
    st = rec["style"]
    if tag == "SVG" or in_svg:
        return "svg"
    if tag in IMG_TAGS:
        return "image"
    bg = st.get("background-image")
    if bg and bg != "none" and "url(" in bg:
        return "image"
    if rec.get("text") and rec["text"].strip():
        return "text"
    if (st.get("border-top-width") or "0px") != "0px":
        return "box"
    if st.get("background-color") not in _TRANSPARENT:
        return "box"
    return "unknown_box"


# ARIA landmark + region-like composite roles -- the content-free allowlist for the
# additive aria_role field (design §3). A computed role outside this set yields NO
# aria_role; this fixed allowlist is the IP boundary (no author role= text reaches disk).
LANDMARK_ROLES = frozenset({
    "banner", "navigation", "main", "contentinfo", "complementary", "region", "search",
    "form", "article", "menubar", "tablist", "toolbar", "dialog",
})


def landmark_roles(ax_tree, allow=LANDMARK_ROLES):
    """{backendDOMNodeId: role_value} for non-ignored AX nodes whose role.value is in
    `allow`. Reads ONLY role.value -- never name/description/value (accessible-name =
    content). Pure: takes a getFullAXTree result dict, returns a plain dict."""
    out = {}
    for n in (ax_tree or {}).get("nodes", []):
        if n.get("ignored"):
            continue
        bk = n.get("backendDOMNodeId")
        role = (n.get("role") or {}).get("value")
        if bk is not None and role in allow:
            out[bk] = role
    return out


def apply_aria_roles(nodes, node_backend, role_by_backend):
    """Set node['aria_role'] for each node whose backendNodeId carries a landmark role.
    Mutates `nodes` in place; LEAVES THE KEY ABSENT when there is no landmark role
    (conditional, like substrate/pseudo). `node_backend` is {node_id: backendNodeId}."""
    if not node_backend or not role_by_backend:
        return
    for n in nodes:
        r = role_by_backend.get(node_backend.get(n["id"]))
        if r:
            n["aria_role"] = r


def enrich_aria(nodes, node_backend, ev):
    """Attach landmark aria_role to `nodes` when a CDP session is available; NO-OP on
    non-CDP transports (safari/android have no ev.sess). Captures getFullAXTree at the
    page's CURRENT (REST) state -- callers invoke this right after the DOMSnapshot.
    The ONLY new code that touches the transport (the pure cores stay I/O-free).
    aria_role is ADDITIVE/optional: any CDP failure (enable OR getFullAXTree) degrades to
    'no aria_role' rather than failing the shared base capture every path depends on."""
    if not hasattr(ev, "sess"):
        return
    try:
        ev.sess.send("Accessibility.enable", {})
    except Exception:  # noqa: BLE001  enable is best-effort; getFullAXTree often works alone
        pass
    try:
        ax = ev.sess.send("Accessibility.getFullAXTree", {})
    except Exception:  # noqa: BLE001  additive enrichment must NOT fail the base capture
        return
    apply_aria_roles(nodes, node_backend, landmark_roles(ax))


_PCT = re.compile(r"^\s*100(\.0+)?%\s*$")
_LEN = re.compile(r"^\s*-?[0-9.]+(px|rem|em|vw|vh|vmin|vmax)\s*$")


def derive_sizing(st, axis):
    """Map computed CSS to hug|fill|fixed for one axis ('w'|'h'). spec §5.1:
    width:100% / flex-grow>0 / align-self:stretch -> fill;
    width:auto + shrink-to-content -> hug; explicit length -> fixed."""
    prop = "width" if axis == "w" else "height"
    val = (st.get(prop) or "auto").strip()

    def _num(x):
        try:
            return float(x)
        except (TypeError, ValueError):
            return 0.0

    grow = _num(st.get("flex-grow"))
    align_self = (st.get("align-self") or "auto").strip()

    # fill: explicit 100%, or flex-grow on the main axis, or stretch on cross
    if _PCT.match(val):
        return ("fill", "high")
    if grow > 0:
        return ("fill", "high")
    if align_self == "stretch":
        return ("fill", "high")
    # fixed: an explicit length
    if _LEN.match(val):
        return ("fixed", "high")
    # auto / min-content / max-content -> hug (shrink to content)
    if val in ("auto", "min-content", "max-content", "fit-content"):
        return ("hug", "high")
    # anything else (calc(), unknown) -> hug, flagged low
    return ("hug", "low")


def _px(v):
    if not v:
        return None
    m = re.match(r"^(-?[0-9.]+)px$", v.strip())
    return float(m.group(1)) if m else None


def derive_layout(st):
    """Build the spec §5.1 layout object (auto-layout intent) from computed CSS."""
    disp = (st.get("display") or "block").strip()
    if disp == "none":
        mode = "none"
    elif "flex" in disp:
        mode = "flex"
    elif "grid" in disp:
        mode = "grid"
    else:
        mode = "block"
    direction = (st.get("flex-direction") or "row").strip()
    gcols = st.get("grid-template-columns")
    grows = st.get("grid-template-rows")
    pad = [_px(st.get("padding-top")) or 0.0, _px(st.get("padding-right")) or 0.0,
           _px(st.get("padding-bottom")) or 0.0, _px(st.get("padding-left")) or 0.0]
    return {
        "mode": mode,
        "direction": direction,
        "gap": _px(st.get("gap")) or 0.0,
        "pad": pad,
        "justify": (st.get("justify-content") or "normal").strip(),
        "align": (st.get("align-items") or "normal").strip(),
        "grid_cols": gcols if (gcols and gcols != "none") else None,
        "grid_rows": grows if (grows and grows != "none") else None,
    }


def build_parent_map(emitted, parent_index):
    """Map each emitted node id -> the id of its nearest emitted DOM ancestor
    (None for the root). emitted: list of dicts with 'id' + 'dom_index'."""
    dom_to_id = {n["dom_index"]: n["id"] for n in emitted}
    out = {}
    for n in emitted:
        j = parent_index[n["dom_index"]]
        pid = None
        while j is not None and j >= 0:
            if j in dom_to_id:
                pid = dom_to_id[j]
                break
            j = parent_index[j]
        out[n["id"]] = pid
    return out


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _family(fam):
    f = (fam or "").lower()
    if "mono" in f:
        return "mono"
    if "serif" in f and "sans" not in f:
        return "serif"
    return "sans"


def to_skeleton(recs, svg_set, parent_index, url, viewport, page):
    """Assemble the spec §5.1 content-independent skeleton. token_ref defaults
    are placeholders filled by the bundle writer (web_tokens role mapping);
    anim_ref defaults None, filled by the bundle writer motion post-pass.
    Returns (skeleton, node_colors, node_style, node_pseudo, node_backend) where
    node_colors is {node_id: {bg, fg, border}} raw-css — captured here because the
    nodes list is filtered/reordered and colors cannot be re-matched positionally
    afterward.
    node_style is {node_id: sparse-visual-props} (Regime-1 cut 1, content-blind).
    node_pseudo is {node_id: {"::before"|"::after"|"::marker": sparse-style}}
    (Regime-2), keyed to the ORIGINATING element via a direct parentIndex lookup.
    node_backend is {node_id: backendNodeId} — the stable cross-capture join key
    (internal; never written to disk)."""
    emitted = []
    node_colors = {}
    node_style = {}
    node_backend = {}
    for r in recs:
        if r.get("pseudo"):
            continue   # pseudo-elements are not standalone nodes — harvested below
        role = classify(r, in_svg=(r["dom_index"] in svg_set))
        if role is None:
            continue
        st = r["style"]
        sz_w, c_w = derive_sizing(st, axis="w")
        sz_h, c_h = derive_sizing(st, axis="h")
        sz_conf = "low" if "low" in (c_w, c_h) else "high"
        node = {
            "id": len(emitted),
            "role": role,
            "confidence": "low" if role == "unknown_box" else "high",
            "bbox": r["bbox"],
            "z": r["z"],
            "parent": None,  # filled below
            "sizing": {"w": sz_w, "h": sz_h, "confidence": sz_conf},
            "layout": derive_layout(st),
            "token_ref": {"bg": None, "fg": None, "border": None},
            "anim_ref": None,
            "_dom_index": r["dom_index"],  # internal; stripped before emit
        }
        if r.get("href"):
            node["href"] = r["href"]      # CONTENT_KEY -> redact_node strips it on ship; survives in raw _sk.json for in-process resolution
        if r.get("substrate"):
            node["substrate"] = r["substrate"]
        if role == "text":
            size = _px(st.get("font-size"))
            node["font"] = {
                "size": size,
                "weight": int(_num(st.get("font-weight")) or 400),
                "line_height": _px(st.get("line-height")),
                "letter_spacing": _px(st.get("letter-spacing")) or 0.0,
                "family": _family(st.get("font-family")),
                "align": st.get("text-align") or "left",
            }
            node["text_len"] = len((r.get("text") or "").strip())
        node_colors[node["id"]] = {
            "bg": st.get("background-color"),
            "fg": st.get("color"),
            "border": st.get("border-top-color"),
        }
        node_backend[node["id"]] = r.get("backend")
        sv = _collect_style(st)
        if sv:
            node_style[node["id"]] = sv
        emitted.append(node)

    # Regime-2: attach each ::before/::after/::marker to its ORIGINATING element's
    # node id via a DIRECT parent lookup (drop on miss — never reattach to an
    # ancestor). parent_color (for _collect_pseudo's color parent-diff) is the
    # originating node's captured fg. Mirrors the _node_colors/_node_style sidecars.
    dom_to_id = {n["_dom_index"]: n["id"] for n in emitted}
    node_pseudo = {}
    for r in recs:
        ps = r.get("pseudo")
        if ps not in _PSEUDO_SELECTORS:
            continue
        nid = dom_to_id.get(parent_index[r["dom_index"]])
        if nid is None:
            continue
        sv = _collect_pseudo(r["style"], (node_colors.get(nid) or {}).get("fg"))
        if sv:
            # Regime-2 GEOMETRY follow-on: carry the pseudo's OWN rendered bbox (already in
            # r["bbox"], CSS-px, dpr-divided by parse_snapshot) alongside the sparse style.
            # Gate on w>0 AND h>0 — a 0x0 box (bare content:"" with no rendered area) carries
            # no geometry worth shipping. Content-free mechanism (floats); redact_pseudo passes
            # the bbox key through untouched. De-risk §pseudo-element-geometry: real decorative
            # pseudos (divider bars, carets, icons) have own boxes NOT derivable from the parent.
            bb = r.get("bbox") or {}
            if (bb.get("w") or 0) > 0 and (bb.get("h") or 0) > 0:
                sv = {**sv, "bbox": bb}
            node_pseudo.setdefault(nid, {})["::" + ps] = sv

    pm = build_parent_map(
        [{"id": n["id"], "dom_index": n["_dom_index"]} for n in emitted],
        parent_index,
    )
    for n in emitted:
        n["parent"] = pm[n["id"]]
        del n["_dom_index"]

    skeleton = {
        "schema": "probe-skeleton/2",
        "url": url,
        "viewport": viewport,
        "page": page,
        "nodes": emitted,
    }
    return skeleton, node_colors, node_style, node_pseudo, node_backend


# JS run before capture: jump to top + neutralize scroll-driven transforms so
# DOMSnapshot reads REST bounds (spec §4 capture-state protocol). Kept
# SYNCHRONOUS — `ev.ev` does not awaitPromise; we sleep in Python for the reflow.
_REST_JS = "(() => { window.scrollTo(0, 0); " \
           "if (window.lenis && window.lenis.scrollTo) window.lenis.scrollTo(0, {immediate:true}); " \
           "return true; })()"


def _backing_scale(ev):
    """Real DOMSnapshot device-px ÷ CSS-px ratio, measured via Page.getLayoutMetrics
    (layoutViewport.clientWidth = device px, cssLayoutViewport.clientWidth = CSS px).

    Unlike JS devicePixelRatio this survives an Emulation deviceScaleFactor override
    on a HEADED retina display (#56): the override collapses JS dpr to 1, but
    getLayoutMetrics and DOMSnapshot both keep the true backing scale (proven live
    2026-05-29: layoutViewport 2560 / cssLayoutViewport 1280 under dsf:1). Snapped to
    the nearest standard display scale {1,1.5,2,3} as a sub-pixel noise guard; an
    exotic fractional display falls back to the raw measured ratio; missing metrics
    (non-CDP / degenerate) fall back to 1.0 (no-op).

    Snap set covers the standard display scales {1, 1.25, 1.5, 1.75, 2, 2.5, 3}
    (mac retina 2/3, Windows 125/150/175%, common Android 2.5); the ±0.06 band is
    tight enough that a genuine non-standard ratio (e.g. 2.4, Pixel's 2.625) stays
    raw rather than mis-snapping."""
    try:
        lm = ev.sess.send("Page.getLayoutMetrics", {})
    except AttributeError:
        # non-CDP transport (no .sess) → 1.0 no-op. A real CDP/transport error is
        # NOT swallowed: it propagates rather than silently returning 1.0, which on
        # a retina display would re-arm the exact 2× coordinate bug this fixes.
        return 1.0
    dev = (lm.get("layoutViewport") or {}).get("clientWidth")
    css = (lm.get("cssLayoutViewport") or {}).get("clientWidth")
    if not dev or not css:
        return 1.0
    raw = dev / css
    for c in (1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0):
        if abs(c - raw) <= 0.06:
            return c
    return raw


def _snapshot_skeleton(ev, url, width=None):
    """Force REST + capture ONE DOMSnapshot at the page's CURRENT state — NO
    navigate. Split out of _capture_one so callers that drive non-URL state
    (web_states / G4) can re-snapshot AFTER a trigger without reloading and
    losing that state. Returns (skeleton, layout, page, node_backend) where
    node_backend is {node_id: backendNodeId} — the cross-capture join key used by
    the theme path (internal; never written to disk). _REST_JS only scrolls to
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

    # DOMSnapshot bounds are device px. The live path (width is None) divides by
    # the page's real devicePixelRatio — verified correct on retina (2560→1280 CSS).
    # The --viewports path (width set) forces Emulation deviceScaleFactor:1, which on
    # a HEADED retina display collapses JS devicePixelRatio to 1 while DOMSnapshot
    # bounds stay at the real backing scale (2560) → dividing by JS dpr would leave
    # coords 2× too large (#56). So measure the true device→CSS ratio from
    # Page.getLayoutMetrics, which keeps the real scale under the override.
    eff_dpr = _backing_scale(ev) if width is not None else (layout["dpr"] or 1.0)
    recs = parse_snapshot(snap, WANT_STYLES, dpr=eff_dpr)
    svg_set = set()
    parent_index = None
    for doc in snap["documents"]:
        svg_set |= svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    # Record the dpr we actually normalized by (eff_dpr), NOT JS layout["dpr"]: under
    # the --viewports override JS dpr lies (1) while eff_dpr is the true backing scale
    # (2). Recording layout["dpr"] would self-report a dpr inconsistent with the
    # already-divided bboxes and trip the same-dpr contract for downstream consumers
    # (bundle_writer propagates this to meta.dpr).
    sk, node_colors, node_style, node_pseudo, node_backend = to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # bundle_writer reads these; serialize with string keys (JSON has no int keys)
    sk["_node_colors"] = {str(k): v for k, v in node_colors.items()}
    sk["_node_style"] = {str(k): v for k, v in node_style.items()}
    sk["_node_pseudo"] = {str(k): v for k, v in node_pseudo.items()}
    enrich_aria(sk["nodes"], node_backend, ev)
    return sk, layout, page, node_backend


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


def capture_with_themes(ev, engine, url, labels, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton under pinned default media, then for each theme
    `label` recapture under that single-axis condition and diff full resolved
    styles vs base (THEME_PROPS); attach per-condition deltas as the _node_theme
    sidecar (keyed by node id; backendNodeId stays internal). Base + every
    condition use identical capture params (phantom-diff guard, design §3).
    Clears emulation in finally so the operator's tab is left unpolluted.

    Note: base styles are captured a second time via _styles_by_backend right
    after the base _capture_one (still under pinned base, no navigate). This
    deliberate extra snapshot avoids threading raw styles out of _capture_one;
    backendNodeId is stable so the two base captures join exactly."""
    try:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": BASE_FEATURES})
        sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
        base_styles = _styles_by_backend(ev)
        per_condition = {}
        for label in labels:
            ev.sess.send("Emulation.setEmulatedMedia",
                         {"features": _condition_features(label)})
            time.sleep(0.3)   # let the restyle settle before recapture
            cond_styles = _styles_by_backend(ev)
            delta = _theme.diff_theme(base_styles, cond_styles, THEME_PROPS)
            per_condition[label] = _theme.rekey_by_node_id(delta, node_backend)
        node_theme = _theme.build_node_theme(per_condition)
        sk["_node_theme"] = {str(k): v for k, v in node_theme.items()}
        return sk
    finally:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": []})


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
    is left unpolluted (the analogue of capture_with_themes clearing emulation).

    Push-drop ceiling: any element backendNodeId that
    DOM.pushNodesByBackendIdsToFrontend fails to resolve to a frontend nodeId is
    silently dropped from the force-set (those nodes get no delta); this is a
    distinct micro-ceiling from the diff-core display:none drop-on-miss. Host
    probe F2 observed no unresolved ids in practice."""
    sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
    recs = _snapshot_recs(ev)                          # base; tags needed for element set
    base_styles = _theme.styles_by_backend(recs)
    elem = element_backends(recs)
    ev.sess.send("DOM.enable", {})   # left enabled intentionally — session closes in
    ev.sess.send("CSS.enable", {})   # the caller's finally: ev.close() right after capture
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
            time.sleep(0.2)   # let the forced restyle settle before recapture (a
            #                   synchronous same-engine pseudo-class restyle, no navigate
            #                   /reflow — settles faster than media-emulation, hence < the
            #                   0.3s capture_with_themes uses)
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


def capture_with_breakpoints(ev, engine, url, widths, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton at the WIDEST width, then for each narrower width
    re-emulate the viewport (Emulation.setDeviceMetricsOverride, NO navigate) and diff
    full resolved styles vs base over RESPONSIVE_PROPS; attach per-width deltas as the
    _node_responsive sidecar (keyed by node id; backendNodeId stays internal).

    Width override is GLOBAL (one condition per capture), so — unlike the per-node
    forcePseudoState path — there is no co-occurrence chimera and no
    DOM.pushNodesByBackendIdsToFrontend round-trip. backendNodeId is stable across the
    overrides on one navigate (probe R2) so base<->width join exactly. Base + every width
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
        # NB: the pure _theme.styles_by_backend transform fed by _snapshot_recs(ev,
        # RESPONSIVE_PROPS) — NOT the module-level _styles_by_backend(ev) wrapper, which
        # would snapshot the hardcoded WANT_STYLES (wrong prop list for the reflow diff).
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
    anims_by_backend = {}
    for backend, front in zip(cand_backends, node_ids):
        if not front:
            continue
        try:
            ms = ev.sess.send("CSS.getMatchedStylesForNode", {"nodeId": front})
        except RuntimeError:
            # On a real page a candidate backendNodeId can push to a NON-Element node
            # (text/pseudo/detached); CDP then raises "Node is not an Element". Drop that
            # single candidate rather than abort the whole capture (drop-on-error, in line
            # with the drop-on-miss philosophy below).
            continue
        anims = _keyframes.parse_keyframes(ms.get("cssKeyframesRules") or [],
                                           anim_by_backend.get(backend, {}),
                                           ANIMATABLE_PROPS)
        if anims:
            anims_by_backend[backend] = anims
    by_node = _theme.rekey_by_node_id(anims_by_backend, node_backend)
    sk["_node_keyframes"] = {str(k): v for k, v in by_node.items()}
    return sk


def capture_with_reduced_motion(ev, engine, url, max_wait=DEFAULT_MAX_WAIT):
    """Capture the base skeleton under emulated prefers-reduced-motion:no-preference, then
    recapture MOTION_PROPS under :reduce and diff vs base; attach the per-node delta as the
    _node_reduced_motion sidecar (keyed by node id; backendNodeId stays internal). One
    navigate, single condition. Mirrors capture_with_themes (the _theme pure core does the
    backendNodeId->node_id rekey via rekey_by_node_id, then build_node_theme transposes to
    {node_id: {"reduce": delta}}). MOTION_PROPS is snapshotted explicitly because it is NOT
    a subset of WANT_STYLES.

    CDP-only (the caller guards on hasattr(ev, "sess")). Ceiling (design §6): captures the
    DECLARED reduced-motion adaptation (computed-prop delta) only — JS honoring
    matchMedia('(prefers-reduced-motion: reduce)') is out of scope (web_anim domain). Clears
    emulation in finally so the operator's tab is left unpolluted."""
    try:
        ev.sess.send("Emulation.setEmulatedMedia",
                     {"features": [{"name": "prefers-reduced-motion", "value": "no-preference"}]})
        sk, _layout, _page, node_backend = _capture_one(ev, engine, url, max_wait=max_wait)
        base = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))
        ev.sess.send("Emulation.setEmulatedMedia",
                     {"features": [{"name": "prefers-reduced-motion", "value": "reduce"}]})
        time.sleep(0.3)   # let the restyle settle before recapture (mirror capture_with_themes)
        cond = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))
        delta = _theme.diff_theme(base, cond, MOTION_PROPS)
        per_condition = {"reduce": _theme.rekey_by_node_id(delta, node_backend)}
        node_rm = _theme.build_node_theme(per_condition)
        sk["_node_reduced_motion"] = {str(k): v for k, v in node_rm.items()}
        return sk
    finally:
        ev.sess.send("Emulation.setEmulatedMedia", {"features": []})


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
    CONTAINER_PROPS + ["container-type"] (phantom-diff); the diff universe is CONTAINER_PROPS only (container-type is
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


def _capture_one(ev, engine, url, width=None, max_wait=DEFAULT_MAX_WAIT):
    """Navigate (with adaptive settle), force REST, capture one DOMSnapshot;
    return (skeleton, layout, page, node_backend). Stamps the settle provenance onto the
    skeleton as `settle` (content-free: counts/flags only) so the bundle is honest
    about whether the snapshot likely caught a stabilized state.

    `width` (multi-breakpoint capture): override the layout-viewport width via
    CDP Emulation before snapshotting, so bboxes reflect that breakpoint. CDP
    reverts the override when the inspector session closes, so the caller's
    open tab is left untouched. No-op on non-CDP transports."""
    settle = navigate(ev, engine, url, max_wait=max_wait)
    sk, layout, page, node_backend = _snapshot_skeleton(ev, url, width=width)
    sk["settle"] = settle
    return sk, layout, page, node_backend


def infer_sizing_from_breakpoints(observations, grow_eps=2.0):
    """spec §5.1: infer sizing from multi-breakpoint bbox-deltas when no DOM
    sizing is available. A dimension that grows with the viewport = fill;
    constant = fixed. Always confidence:low (inferred, not read from CSS).
    observations: [{vw, w, h}, ...] sorted-agnostic; needs >=2 entries."""
    if len(observations) < 2:
        return {"w": "fixed", "h": "fixed", "confidence": "low"}
    obs = sorted(observations, key=lambda o: o["vw"])
    lo, hi = obs[0], obs[-1]

    def axis(dim):
        return "fill" if (hi[dim] - lo[dim]) > grow_eps else "fixed"

    return {"w": axis("w"), "h": axis("h"), "confidence": "low"}


def _center_xy(b):
    return (b["x"] + b["w"] / 2, b["y"] + b["h"] / 2)


def merge_breakpoints(ref, others, radius=40):
    """For each ref node with low-confidence DOM sizing, gather its bbox across
    the reference + other-viewport skeletons (matched by nearest center on the
    y-axis only — full-width nodes shift x-center with viewport) and overwrite
    sizing with the cross-breakpoint inference. High-confidence DOM sizing is
    preserved (spec §8: DOM reads win)."""
    ref_vw = ref["viewport"]["w"]
    for n in ref["nodes"]:
        if n.get("sizing", {}).get("confidence") != "low":
            continue
        obs = [{"vw": ref_vw, "w": n["bbox"]["w"], "h": n["bbox"]["h"]}]
        cn = _center_xy(n["bbox"])
        for o in others:
            ovw = o["viewport"]["w"]
            best, best_d = None, None
            for m in o["nodes"]:
                mc = _center_xy(m["bbox"])
                d = abs(cn[1] - mc[1])  # y-axis only: fill nodes shift x-center
                if d <= radius and (best_d is None or d < best_d):
                    best, best_d = m, d
            if best is not None:
                obs.append({"vw": ovw, "w": best["bbox"]["w"], "h": best["bbox"]["h"]})
        if len(obs) >= 2:
            n["sizing"] = infer_sizing_from_breakpoints(obs)
    return ref


def _build_argparser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=None, help="write skeleton.json here")
    p.add_argument("--viewports", default=None,
                   help="comma widths e.g. 390,768,1440; multi-breakpoint sizing inference")
    p.add_argument("--themes", default=None,
                   help="comma labels from {dark,forced-colors,contrast}; capture "
                        "per-node resolved style deltas under each emulated-media "
                        "condition into the _node_theme sidecar")
    p.add_argument("--pseudo-states", default=None, dest="pseudo_states",
                   help="comma labels from {hover,focus,active}; capture per-node "
                        "resolved style deltas under each forced CSS pseudo-class "
                        "(CSS.forcePseudoState) into the _node_pseudo_state sidecar")
    p.add_argument("--breakpoints", nargs="?", const=DEFAULT_BREAKPOINTS, default=None,
                   help="comma widths e.g. 390,768,1440 (bare --breakpoints uses the "
                        "default 390,768,1440); capture per-node resolved-style REFLOW "
                        "deltas across viewport widths (Emulation.setDeviceMetricsOverride, "
                        "backendNodeId join) into the _node_responsive sidecar. DISTINCT "
                        "from --viewports (coarse fill/fixed sizing inference, positional "
                        "join, merged skeleton).")
    p.add_argument("--keyframes", action="store_true", default=False,
                   help="capture per-node CSS @keyframes animation timelines "
                        "(CSS.getMatchedStylesForNode, backendNodeId join) into the "
                        "_node_keyframes sidecar. Content-free: keyframe offsets + "
                        "animated-property values + timing; the @keyframes NAME is never "
                        "persisted. Authored-path (covers finished/not-started anims).")
    p.add_argument("--reduced-motion", action="store_true", default=False,
                   help="capture the per-node computed-style delta under emulated "
                        "prefers-reduced-motion:reduce (Emulation.setEmulatedMedia, "
                        "backendNodeId join) into the _node_reduced_motion sidecar. "
                        "Content-free: changed motion-prop values (animation/transition off, "
                        "scroll-behavior). Declared-variant only (JS honoring is out of scope).")
    p.add_argument("--form-states", action="store_true", default=False, dest="form_states",
                   help="capture the per-node computed-style delta when form controls are forced "
                        "into :checked / :disabled (CSS.forcePseudoState on state-eligible "
                        "elements via DOM.querySelectorAll, backendNodeId join) into the "
                        "_node_form_state sidecar. Content-free: changed form-state-prop values "
                        "(opacity/accent-color/cursor/color/bg/outline). CSS-toggle combinator "
                        "deltas land on the sibling node.")
    p.add_argument("--container-queries", nargs="?", const=DEFAULT_CONTAINER_WIDTHS,
                   default=None, dest="container_queries",
                   help="comma container widths e.g. 240,480,720 (bare --container-queries "
                        "uses the default 240,480,720); capture per-node resolved-style "
                        "restyle deltas as each fixed-width inline-size @container query "
                        "container is forced to those widths (DOM width mutation, "
                        "backendNodeId join) into the _node_container sidecar. Closes the R3c "
                        "fixed-width @container ceiling; DISTINCT from --breakpoints "
                        "(viewport-tracking containers only).")
    p.add_argument("--max-wait", type=float, default=DEFAULT_MAX_WAIT, dest="max_wait",
                   help="adaptive-settle cap in seconds (default %(default)s; "
                        "raise for slow-hydrate targets, e.g. --max-wait 30)")
    p.add_argument("--sweep", action="store_true", default=False,
                   help="APPEND-class virtualization: scroll-settle sweep + below_fold merge (opt-in)")
    p.add_argument("--sweep-steps", type=int, default=8, dest="sweep_steps",
                   help="bounded sweep step count (default 8)")
    add_transport_args(p)  # supplies --url (shared transport flag) + device flags
    return p


def main() -> int:
    args = _build_argparser().parse_args()
    if not args.url:
        die("web_skeleton needs --url (the page to capture a skeleton of).")

    if args.themes:
        labels = [s.strip() for s in args.themes.split(",") if s.strip()]
        bad = [l for l in labels if l not in CONDITION_OVERRIDE]
        if bad:
            die(f"web_skeleton --themes: unknown {bad}; choose from "
                f"{sorted(CONDITION_OVERRIDE)}")
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --themes needs a CDP transport "
                    "(Emulation.setEmulatedMedia). Use chrome host / --cdp-port.")
            out_obj = capture_with_themes(ev, engine, args.url, labels,
                                          max_wait=args.max_wait)
        finally:
            ev.close()
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
    elif args.keyframes:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --keyframes needs a CDP transport "
                    "(CSS.getMatchedStylesForNode). Use chrome host / --cdp-port.")
            out_obj = capture_with_keyframes(ev, engine, args.url, max_wait=args.max_wait)
        finally:
            ev.close()
    elif args.reduced_motion:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton --reduced-motion needs a CDP transport "
                    "(Emulation.setEmulatedMedia). Use chrome host / --cdp-port.")
            out_obj = capture_with_reduced_motion(ev, engine, args.url, max_wait=args.max_wait)
        finally:
            ev.close()
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
    elif args.viewports:
        widths = [int(w) for w in args.viewports.split(",") if w.strip()]
        skeletons = []
        for w in sorted(widths, reverse=True):   # reference = widest first
            engine, ev, device = resolve_web_eval(args)
            try:
                if not hasattr(ev, "sess"):
                    die("web_skeleton --viewports needs a CDP transport "
                        "(Emulation width override). Use chrome host / --cdp-port.")
                sk, _, _, _ = _capture_one(ev, engine, args.url, width=w,
                                           max_wait=args.max_wait)
            finally:
                ev.close()
            skeletons.append(sk)
        out_obj = merge_breakpoints(skeletons[0], skeletons[1:])
    else:
        engine, ev, device = resolve_web_eval(args)
        try:
            if not hasattr(ev, "sess"):
                die("web_skeleton needs a CDP transport (chrome host / --android / --cdp-port).")
            out_obj, _, _, _ = _capture_one(ev, engine, args.url,
                                            max_wait=args.max_wait)
            if args.sweep:
                import _virt  # function-local: keeps _virt's pure core off the default path
                sc = _virt._scrollable(ev)
                if sc["sh"] > sc["ih"]:                       # in-class gate (sh>ih)
                    sweep_sks = _virt.sweep_skeletons(ev, args.url, steps=args.sweep_steps)
                    out_obj = _virt.merge_skeletons(out_obj, sweep_sks)   # out_obj IS the REST skeleton
                else:                                          # out-of-class: REST-only + log
                    emit_json({"sweep": "skipped", "reason": "out_of_class_sh_le_ih",
                               "sh": sc["sh"], "ih": sc["ih"]})
        finally:
            ev.close()

    if args.out:
        Path(args.out).write_text(json.dumps(out_obj, indent=2))
        emit_json({"ok": True, "nodes": len(out_obj["nodes"]), "out": args.out,
                   "viewport": out_obj["viewport"], "page": out_obj["page"]})
    else:
        emit_json(out_obj)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
