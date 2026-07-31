#!/usr/bin/env python3
"""bundle_writer — assemble the spec §5 portable bundle/ directory from a
web_skeleton skeleton + web_tokens tokens + an external motion capture
(web_anim/flipbook) + node-role-derived asset slots. Generic and
content-independent: motion is read from a file, never baked in. Pure assembly
funcs are unit-tested; main() writes the files."""
from __future__ import annotations
import argparse
import json
import time
from pathlib import Path

from _common import emit_json
import web_tokens as wt
import content_firewall as cf
import slots as _slots
import _substrate
import _style


class ContentLeak(RuntimeError):
    """Raised when audit_bundle finds content in a written bundle/."""


def match_motion(nodes, motion_rows, band=400.0):
    """Assign each motion row to the nearest node within `band` px of its anchor.

    A node is a candidate when its bbox top (REST page-y) is within `band` of the
    row's `anchor`. Among candidates, the row binds to the node minimizing
    distance: when the row carries `anchor_x` (REST center-x), distance is
    Euclidean over (center-x, y) so CO-LOCATED movers — two elements at the same y
    but different x, e.g. mirror hero words — bind to their correct DISTINCT nodes
    instead of collapsing onto whichever shares the y. Without `anchor_x` it is
    y-only (back-compat with older, x-blind captures).

    Sets node['anim_ref'] in place as a LIST (appends each bound row name) so a
    node animated on several channels / by several movers keeps all of them rather
    than overwriting down to the last. Returns the motion.json rows:
    [{node_id, name, easing, cubic_bezier, amplitude, axis, window, class,
      source, rms, [anchor_x]}, ...]."""
    out = []
    for row in motion_rows:
        anchor = row["anchor"]
        anchor_x = row.get("anchor_x")
        best, best_d = None, None
        for n in nodes:
            b = n["bbox"]
            dy = abs(b["y"] - anchor)
            if dy > band:
                continue
            if anchor_x is None:
                d = dy
            else:
                node_cx = b["x"] + b["w"] / 2.0
                d = (dy * dy + (node_cx - anchor_x) ** 2) ** 0.5
            if best_d is None or d < best_d:
                best, best_d = n, d
        if best is None:
            continue
        # anim_ref is a list of every motion bound to this node (never overwrite).
        ref = best.get("anim_ref")
        if isinstance(ref, list):
            ref.append(row["name"])
        else:
            best["anim_ref"] = [row["name"]]
        bound = {
            "node_id": best["id"], "name": row["name"], "easing": row["easing"],
            "cubic_bezier": row["cubic_bezier"], "amplitude": row["amplitude"],
            "axis": row["axis"], "window": row["window"], "class": row["klass"],
            "source": row["source"], "rms": row["rms"],
        }
        if anchor_x is not None:
            bound["anchor_x"] = anchor_x
        out.append(bound)
    return out


def _aspect(b):
    return round(b["w"] / b["h"], 4) if b["h"] else None


def derive_slots(nodes):
    """spec §5.3 asset slots, one per swappable node (image/text/svg).
    box/unknown_box are structural and get no slot."""
    slots = []
    for n in nodes:
        role = n["role"]
        b = n["bbox"]
        if role == "image":
            slots.append({"node_id": n["id"], "kind": "image",
                          "bbox": b, "aspect": _aspect(b),
                          "sizing": n.get("sizing")})
        elif role == "text":
            tl = n.get("text_len") or 0
            slots.append({"node_id": n["id"], "kind": "text",
                          "bbox": b, "font": n.get("font"),
                          "sizing": n.get("sizing"),
                          "suggested_max_glyphs": int(round(tl * 1.5))})
        elif role == "svg":
            slots.append({"node_id": n["id"], "kind": "svg",
                          "bbox": b, "aspect": _aspect(b), "vec_ref": None})
    return slots


def _nearest_role(css, palette):
    """Nearest semantic role name (by RGB euclidean distance) to a css color.
    Returns None only when the css is transparent/unparseable or the palette has
    no parseable entries — there is no distance ceiling, so any real color maps
    to its closest role."""
    rgb = wt.parse_color(css)
    if rgb is None:
        return None
    best, best_d = None, None
    for name, hexval in palette.items():
        prgb = wt.parse_color(hexval)
        if prgb is None:
            continue
        d = sum((a - b) ** 2 for a, b in zip(rgb, prgb)) ** 0.5
        if best_d is None or d < best_d:
            best, best_d = name, d
    return best


def apply_token_refs(nodes, palette, node_colors):
    """Resolve each node's captured bg/fg/border colors to the nearest tokens.json
    semantic role name. node_colors: {node_id: {bg, fg, border}} raw css."""
    for n in nodes:
        cols = node_colors.get(n["id"], {})
        n["token_ref"] = {
            "bg": _nearest_role(cols.get("bg"), palette),
            "fg": _nearest_role(cols.get("fg"), palette),
            "border": _nearest_role(cols.get("border"), palette),
        }


def apply_node_style(nodes, node_style):
    """Attach each node's captured visual-style map as node["style"], with external/
    data: url() redacted by _style. node_style: {node_id: {prop: raw resolved value}}.
    Runs BEFORE cf.redact_node (a content-key blacklist that preserves the `style`
    key). A node with no captured style gets no `style` field."""
    if not node_style:
        return
    for n in nodes:
        sv = node_style.get(n["id"])
        if sv:
            n["style"] = _style.redact_node_styles(sv)


def apply_node_pseudo(nodes, node_pseudo):
    """Attach each node's captured pseudo-element map as node["pseudo"], redacted by
    _style (content -> "<text>"; external/data url() -> url("<asset>")). node_pseudo:
    {node_id: {selector: {prop: raw value}}}. Runs BEFORE cf.redact_node, which
    preserves the `pseudo` key (not a CONTENT_KEYS entry; redact_node filters only
    top-level keys, so the nested redacted content survives). No entry -> no field."""
    if not node_pseudo:
        return
    for n in nodes:
        pv = node_pseudo.get(n["id"])
        if pv:
            n["pseudo"] = _style.redact_pseudo(pv)


def apply_node_theme(nodes, node_theme):
    """Attach each node's theme-delta map as node["theme"], redacted by _style
    (content -> "<text>"; external/data url() -> url("<asset>"); raw rgb kept).
    node_theme: {node_id: {condition: {prop: raw value}}}. Runs BEFORE
    cf.redact_node, which preserves the `theme` key (not a CONTENT_KEYS entry;
    redact_node filters only top-level keys, so the nested redacted map survives).
    No entry -> no field."""
    if not node_theme:
        return
    for n in nodes:
        tv = node_theme.get(n["id"])
        if tv:
            n["theme"] = _style.redact_theme(tv)


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


def apply_node_reduced_motion(nodes, node_rm):
    """Attach each node's reduced-motion computed-style delta as node["reduced_motion"],
    redacted by _style (flat {label:{prop:value}} shape; redact_reduced_motion is a
    redact_theme alias). node_rm: {node_id: {"reduce": {prop: value}}}. Runs BEFORE
    cf.redact_node, which preserves the `reduced_motion` key (not a CONTENT_KEYS entry).
    No entry / empty delta -> no field. This is the declared prefers-reduced-motion:reduce
    adaptation, sibling to the theme/pseudo_state/responsive deltas (same shape)."""
    if not node_rm:
        return
    for n in nodes:
        rv = node_rm.get(n["id"])
        if rv:
            n["reduced_motion"] = _style.redact_reduced_motion(rv)


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


def assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None,
             node_style=None, node_pseudo=None, node_theme=None, node_pseudo_state=None,
             node_responsive=None, node_keyframes=None, node_reduced_motion=None,
             node_form_state=None, node_container=None):
    """Build the in-memory bundle: meta + skeleton (with anim_ref/token_ref
    filled) + tokens + motion + assets/manifest. Mutates skeleton nodes in place
    to set anim_ref and token_ref."""
    nodes = skeleton["nodes"]
    palette = tokens.get("palette", {})
    apply_token_refs(nodes, palette, node_colors)
    apply_node_style(nodes, node_style)
    apply_node_pseudo(nodes, node_pseudo)
    apply_node_theme(nodes, node_theme)
    apply_node_pseudo_state(nodes, node_pseudo_state)
    apply_node_responsive(nodes, node_responsive)
    apply_node_keyframes(nodes, node_keyframes)
    apply_node_reduced_motion(nodes, node_reduced_motion)
    apply_node_form_state(nodes, node_form_state)
    apply_node_container(nodes, node_container)
    motion = match_motion(nodes, motion_rows)
    manifest = _slots.build_slots(nodes)   # typed slots + index (supersedes derive_slots)
    substrate = _substrate.collect_substrate(nodes, url=skeleton.get("url"))
    skeleton["nodes"] = [cf.redact_node(n) for n in nodes]   # R3: strip content keys from emitted nodes
    bf = skeleton.get("below_fold")
    if bf and bf.get("shapes"):
        bf["shapes"] = [cf.redact_node(r) for r in bf["shapes"]]
    meta = {
        "url": skeleton.get("url"),
        "viewport": skeleton.get("viewport"),
        "page": skeleton.get("page"),
        "dpr": skeleton.get("viewport", {}).get("dpr"),
        "schema": skeleton.get("schema"),
    }
    meta.update(meta_extra or {})
    bundle = {
        "meta": meta,
        "skeleton": skeleton,
        "tokens": tokens,
        "motion": motion,
        "manifest": manifest,
        "substrate": substrate,
    }
    if states is not None:
        bundle["states"] = states   # G4 interaction-state artifact (optional)
    return bundle


def write_bundle(bundle, out_dir):
    """Write the bundle to the spec §5 directory layout."""
    root = Path(out_dir)
    (root / "assets").mkdir(parents=True, exist_ok=True)
    (root / "meta.json").write_text(json.dumps(bundle["meta"], indent=2))
    (root / "skeleton.json").write_text(json.dumps(bundle["skeleton"], indent=2))
    (root / "tokens.json").write_text(json.dumps(bundle["tokens"], indent=2))
    (root / "motion.json").write_text(json.dumps(bundle["motion"], indent=2))
    (root / "assets" / "manifest.json").write_text(
        json.dumps(bundle["manifest"], indent=2))
    (root / "substrate.json").write_text(json.dumps(bundle["substrate"], indent=2))
    if "states" in bundle:
        (root / "states.json").write_text(json.dumps(bundle["states"], indent=2))
    viol = cf.audit_bundle(root)
    if viol:
        # content-free: a prose violation carries a `sample` of up to 40 chars of the
        # leaked content; never embed it in the exception message (which reaches
        # stderr/stdout). Surface only kind + file.
        safe = [{"kind": v.get("kind"), "file": v.get("file")} for v in viol[:5]]
        raise ContentLeak(
            f"content leak in bundle {out_dir}: {len(viol)} violation(s); first {len(safe)}: {safe}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--skeleton", required=True, help="skeleton.json from web_skeleton")
    p.add_argument("--tokens", required=True, help="tokens.json from web_tokens")
    p.add_argument("--out", required=True, help="bundle/ output directory")
    p.add_argument("--motion", default=None,
                   help="motion.json rows from a web_anim/flipbook capture "
                        "(list of {name,anchor,easing,cubic_bezier,amplitude,"
                        "axis,window,klass,source,rms}); omitted -> no motion")
    args = p.parse_args()

    with open(args.skeleton) as f:
        skeleton = json.load(f)
    with open(args.tokens) as f:
        tokens = json.load(f)

    # node_colors comes from the skeleton's _node_colors sidecar (string keys in
    # JSON -> int node ids). Empty dict if absent (token_ref stays null).
    raw_colors = skeleton.pop("_node_colors", {})
    node_colors = {int(k): v for k, v in raw_colors.items()}

    raw_style = skeleton.pop("_node_style", {})
    node_style = {int(k): v for k, v in raw_style.items()}

    raw_pseudo = skeleton.pop("_node_pseudo", {})
    node_pseudo = {int(k): v for k, v in raw_pseudo.items()}

    raw_theme = skeleton.pop("_node_theme", {})
    node_theme = {int(k): v for k, v in raw_theme.items()}
    raw_pseudo_state = skeleton.pop("_node_pseudo_state", {})
    node_pseudo_state = {int(k): v for k, v in raw_pseudo_state.items()}
    raw_responsive = skeleton.pop("_node_responsive", {})
    node_responsive = {int(k): v for k, v in raw_responsive.items()}
    raw_keyframes = skeleton.pop("_node_keyframes", {})
    node_keyframes = {int(k): v for k, v in raw_keyframes.items()}
    raw_reduced_motion = skeleton.pop("_node_reduced_motion", {})
    node_reduced_motion = {int(k): v for k, v in raw_reduced_motion.items()}
    raw_form_state = skeleton.pop("_node_form_state", {})
    node_form_state = {int(k): v for k, v in raw_form_state.items()}
    raw_container = skeleton.pop("_node_container", {})
    node_container = {int(k): v for k, v in raw_container.items()}
    skeleton.pop("_node_backend", None)   # internal join key — never reaches disk

    motion_rows = []
    if args.motion:
        with open(args.motion) as f:
            motion_rows = json.load(f)

    bundle = assemble(skeleton, tokens, node_colors, motion_rows,
                      meta_extra={"timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                             time.gmtime())},
                      node_style=node_style, node_pseudo=node_pseudo,
                      node_theme=node_theme, node_pseudo_state=node_pseudo_state,
                      node_responsive=node_responsive, node_keyframes=node_keyframes,
                      node_reduced_motion=node_reduced_motion,
                      node_form_state=node_form_state,
                      node_container=node_container)
    try:
        write_bundle(bundle, args.out)
    except ContentLeak:
        # Content audit fired. Exit with a distinct, reserved code (3) so orchestrators
        # (site_capture) can classify this as content-suspicious vs a generic failure
        # WITHOUT reading stderr. The ContentLeak message is already content-free
        # (kind+file only, no sample), but we surface only a category here.
        emit_json({"ok": False, "error": "content_audit_failed", "out": args.out})
        return 3
    emit_json({"ok": True, "out": args.out, "nodes": len(skeleton["nodes"]),
               "motion_rows": len(bundle["motion"]),
               "slots": len(bundle["manifest"]["slots"])})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
