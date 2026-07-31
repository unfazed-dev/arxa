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

    if expanded == "true" or rec.get("hasOpen"):
        return None
    if tag in _DISCLOSURE_TAGS:
        return {"kind": "disclosure", "action": "click"}
    if haspopup and haspopup != "false":
        return {"kind": "menu", "action": "click"}
    if expanded == "false":
        return {"kind": "disclosure", "action": "click"}
    return None


def _nodes(sk):
    """Accept either a skeleton dict ({"nodes": [...]}) or a bare node list."""
    return sk.get("nodes", []) if isinstance(sk, dict) else (sk or [])


def _center(b):
    return (b["x"] + b["w"] / 2.0, b["y"] + b["h"] / 2.0)


def _matches_rest(a, rest_nodes, radius):
    """True if after-node `a` corresponds to a REST node (same element, possibly
    reflowed) — i.e. it is NOT revealed content. A match is same-role AND EITHER
    (a) center within `radius` px on both axes AND size within `radius` px on both
    dims (a small reflow shift = the SAME node), OR (b) top-left corners coincide
    within `radius` (the SAME element grew/reflowed in place — a page-root container
    like <body>/<html> growing taller is reflow, not revealed content).

    Extracted from diff_skeletons so diff_skeletons and build_component share ONE
    definition. See diff_skeletons' docstring for the documented under-count limit."""
    ab = a["bbox"]
    ac = _center(ab)
    for r in rest_nodes:
        if a.get("role") != r.get("role"):
            continue
        rb = r["bbox"]
        rc = _center(rb)
        same_box = (abs(ac[0] - rc[0]) <= radius and abs(ac[1] - rc[1]) <= radius
                    and abs(ab["w"] - rb["w"]) <= radius
                    and abs(ab["h"] - rb["h"]) <= radius)
        reflowed = (abs(ab["x"] - rb["x"]) <= radius and abs(ab["y"] - rb["y"]) <= radius)
        if same_box or reflowed:
            return True
    return False


def diff_skeletons(rest, after, radius=24.0):
    """Return {"appeared": [...], "n_appeared": N}: the after-trigger nodes with
    NO matching REST node. A REST node matches an after node (same role) when EITHER
    (a) center within `radius` px on both axes AND size within `radius` px on both
    dims (a small reflow shift = the SAME node), OR (b) their top-left corners
    coincide within `radius` — the SAME element reflowed/resized in place (a
    page-root container like <body>/<html> growing taller when a panel opens is
    reflow, not revealed content, and must not be counted). Appeared descriptors are
    content-free (role/bbox/z only) — the firewall-safe record of what was revealed.

    LIMIT (inherent, documented — do not "fix" with a size/containment qualifier):
    the corner rule cannot distinguish a grown container from a NEW same-role node
    anchored at the same corner. The notable case is an ORIGIN-ANCHORED full-bleed
    modal/overlay (role 'box', same as <body>): its outer box is corner-matched to
    <body> and EXCLUDED (under-counted). Its non-origin children still count, and a
    grown <body> and a full-screen modal are genuinely both "larger, same corner" —
    no local rule separates them. This is the safe direction (under-, not over-count)
    vs. the alternative of counting every page-growth reflow as revealed content."""
    rest_nodes = _nodes(rest)
    appeared = []
    for a in _nodes(after):
        if not _matches_rest(a, rest_nodes, radius):
            appeared.append({"role": a.get("role"), "bbox": a["bbox"], "z": a.get("z", 0)})
    return {"appeared": appeared, "n_appeared": len(appeared)}


def build_component(rest, after, radius=24.0):
    """Build a reproducible, content-free mini-skeleton of the nodes revealed in
    `after` vs `rest` (post-trigger vs REST skeletons). Returns
    {"n_nodes": N, "nodes": [...]} or None when nothing was revealed.

    Each component node carries the content-free skeleton fields (role, bbox, z,
    sizing, layout, and `font` for text nodes) plus `colors` {bg, fg, border} from
    the after-skeleton's `_node_colors` sidecar, re-rooted with component-local
    parent ids (0..N-1 in revealed order). A component ROOT (its after-parent is a
    REST node, not itself revealed) records that parent as `mount` {role, bbox,
    colors} — or `mount=None` when the after-parent is absent (a document root) or
    unresolvable (a dangling parent id); non-roots have mount=None. The mount
    preserves the attach point AND a
    collapsed origin-anchored full-bleed modal container's backdrop colors (that
    container corner-matches <body>, so _matches_rest treats it as the mount, not a
    revealed node).

    Pure: `after` carries its own `_node_colors`; no browser. `new` uses the SAME
    predicate as diff_skeletons (`not _matches_rest`) over the same after-nodes, so
    n_nodes == that diff's n_appeared — a free cross-check."""
    rest_nodes = _nodes(rest)
    after_nodes = _nodes(after)
    colors = (after.get("_node_colors") if isinstance(after, dict) else None) or {}
    by_id = {n["id"]: n for n in after_nodes}

    new = [n for n in after_nodes if not _matches_rest(n, rest_nodes, radius)]
    if not new:
        return None
    new_ids = {n["id"] for n in new}
    local = {n["id"]: i for i, n in enumerate(new)}

    def _colors(node_id):
        c = colors.get(str(node_id)) or {}
        return {"bg": c.get("bg"), "fg": c.get("fg"), "border": c.get("border")}

    nodes = []
    for n in new:
        cn = {"id": local[n["id"]], "role": n.get("role"), "bbox": n["bbox"],
              "z": n.get("z", 0), "sizing": n.get("sizing"), "layout": n.get("layout"),
              "colors": _colors(n["id"])}
        if "font" in n:
            cn["font"] = n["font"]
        pid = n.get("parent")
        if pid in new_ids:
            cn["parent"] = local[pid]
            cn["mount"] = None
        else:
            cn["parent"] = None
            mp = by_id.get(pid) if pid is not None else None
            cn["mount"] = ({"role": mp.get("role"), "bbox": mp["bbox"],
                            "colors": _colors(pid)} if mp is not None else None)
        nodes.append(cn)
    return {"n_nodes": len(new), "nodes": nodes}
