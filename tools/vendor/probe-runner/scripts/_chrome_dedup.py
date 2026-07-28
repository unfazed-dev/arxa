# scripts/_chrome_dedup.py
#!/usr/bin/env python3
"""G3d shared-chrome dedup (pure core) — structural-template + per-instance lossless deltas.

Reads N per-route skeleton node-lists, dedups recurring chrome landmarks against a structural
template, and emits an artifact that reconstructs each route's nodes LOSSLESSLY (node-set identical,
id-keyed — order is not part of the contract). Lossless by construction: any field whose value
differs from the template is charged as a per-instance exception, and any field present on the
template but absent on the instance is recorded in a per-instance `drop` map (deleted on rebuild) —
so a structural-key match never silently drops an unkeyed field (e.g. a per-route `style`).

Gate provenance: docs/plans/g3d-structural-deltas-chrome-dedup-{design,results}.md. Encoding pin =
bbox-only (template parent/z/confidence, re-base id, charge bbox per instance). No I/O, no CDP."""
from __future__ import annotations

import copy
from collections import Counter, defaultdict

from _shape_key import _KEY_FIELDS  # canonical 20-field order — single source of truth

# --- structural key (re-homed from probe_g3d_structural; volatile + positional excluded) ---
CHROME = frozenset({"banner", "navigation", "contentinfo", "complementary"})
# Structural key = exact key with the 4 volatile fields BLANKED (design §1 DROP_STRUCT).
_DROP_STRUCT = ("token_ref.bg", "token_ref.fg", "token_ref.border", "text_len")
# Positional (re-stored / re-based per instance, never in the structural key):
_POS_TOP = {"id", "parent", "z", "confidence"}
# Volatile (paid as per-instance deltas): token_ref.{bg,fg,border} + text_len.
_VOL_KEYS = (("token_ref", "bg"), ("token_ref", "fg"), ("token_ref", "border"), ("text_len", None))
_VOL_SET = set(_VOL_KEYS)
_MISSING = object()


def _children(nodes):
    bp = defaultdict(list)
    for n in nodes:
        bp[n.get("parent")].append(n)
    return bp


def _roots(nodes):
    ids = {n["id"] for n in nodes}
    return [n for n in nodes if n.get("parent") not in ids]


def _field_vals(n):
    """Read all 20 keyed fields with the SAME nested access + pseudo normalization as
    probe_g3d_dedup._node_key (faithful copy — keeps structural grouping identical to the probe)."""
    lay = n.get("layout") or {}
    sz = n.get("sizing") or {}
    tr = n.get("token_ref") or {}
    f = n.get("font") or {}
    return {
        "role": n.get("role"), "aria_role": n.get("aria_role"),
        "layout.mode": lay.get("mode"), "layout.direction": lay.get("direction"),
        "layout.gap": lay.get("gap"), "layout.pad": lay.get("pad"),
        "layout.justify": lay.get("justify"), "layout.align": lay.get("align"),
        "layout.grid_cols": lay.get("grid_cols"), "layout.grid_rows": lay.get("grid_rows"),
        "sizing.w": sz.get("w"), "sizing.h": sz.get("h"),
        "token_ref.bg": tr.get("bg"), "token_ref.fg": tr.get("fg"), "token_ref.border": tr.get("border"),
        "font.family": f.get("family"), "font.weight": f.get("weight"),
        "text_len": n.get("text_len"), "pseudo": 1 if n.get("pseudo") else 0,
        "substrate": n.get("substrate"),
    }


def _node_key(n):
    """Structural identity = the exact key with the 4 volatile fields blanked. Returns a string,
    mirroring probe_g3d_dedup._node_key(n, drop=DROP_STRUCT) (pipe-joined, str() per field).

    CONVENTION (note for later-task code): unlike the probe's same-named `_node_key(n, drop=())`,
    this module's `_node_key` is STRUCTURAL-ONLY — drop is hardwired to _DROP_STRUCT and there is no
    `drop` param. The dedup core never needs the exact key, so `_subtree` here calls `_node_key(n)`
    positionally without a drop argument (it is NOT a verbatim lift of the probe's `_subtree`)."""
    v = _field_vals(n)
    return "|".join("" if name in _DROP_STRUCT else str(v[name]) for name in _KEY_FIELDS)


def _subtree(node, by_parent):
    """Structural key (string) of a node + its subtree, children in emit order — mirrors
    probe_g3d_dedup._subtree's string form. Isomorphic across two structurally-matching instances,
    so a lock-step walk gives node-to-node correspondence."""
    ck = [_subtree(c, by_parent) for c in by_parent.get(node["id"], [])]
    inner = "(" + ",".join(ck) + ")" if ck else ""
    return _node_key(node) + inner


def _vol_val(n, top, sub):
    if sub is None:
        return n.get(top, _MISSING)
    d = n.get(top)
    return d.get(sub, _MISSING) if isinstance(d, dict) else _MISSING


def _vol_name(top, sub):
    return top if sub is None else top + "." + sub


def _encode_volatile(tmpl, inst):
    """Per-instance volatile delta vs the template node. flags = leaves that differ (1 bit each);
    values = the differing leaf values (lossless). Leaves equal to the template cost only a flag."""
    flags, values = set(), {}
    for top, sub in _VOL_KEYS:
        iv = _vol_val(inst, top, sub)
        if iv is _MISSING:
            continue  # leaf not present on this instance node
        tv = _vol_val(tmpl, top, sub)
        if iv != tv:
            name = _vol_name(top, sub)
            flags.add(name)
            values[name] = iv
    return {"flags": flags, "values": values}


def _apply_volatile(node, tmpl, delta):
    """Reconstruct the instance node's volatile leaves: copy template's, then overwrite the flagged
    ones with the stored values. Mutates `node` in place."""
    for top, sub in _VOL_KEYS:
        name = _vol_name(top, sub)
        if name in delta["values"]:
            val = delta["values"][name]
        else:
            val = _vol_val(tmpl, top, sub)
            if val is _MISSING:
                continue
        if sub is None:
            node[top] = val
        else:
            node.setdefault(top, {})[sub] = val


def _reconstruct_node(tmpl_node, new_id, new_parent, bbox_val, has_bbox, vdelta):
    """Build the template-derived instance node EXACTLY as reconstruct() will, BEFORE exceptions/drop.
    Single source of truth: dedup_chrome simulates with this to compute the lossless patch, and
    reconstruct calls it to build — so the patch is diffed against the real ship path (no drift).
    Re-bases id/parent, overrides bbox (or removes it), and applies the volatile delta."""
    n = copy.deepcopy(tmpl_node)
    n["id"] = new_id
    n["parent"] = new_parent
    if has_bbox:
        n["bbox"] = copy.deepcopy(bbox_val)
    elif "bbox" in n:
        del n["bbox"]
    _apply_volatile(n, tmpl_node, vdelta)
    return n


def _node_patch(recon, inst):
    """The minimal correction turning the template-derived `recon` into the real instance `inst`.
    set_ = {k: inst[k]} for every key whose value differs or is instance-only; drop = keys present in
    recon but absent on inst. Applying set_ then drop to recon yields inst EXACTLY -> lossless by
    construction (covers id/parent/z/confidence AND any unkeyed field: style, tag, extra token_ref
    subkeys, presence mismatches — both directions)."""
    set_ = {k: v for k, v in inst.items() if recon.get(k, _MISSING) != v}
    drop = [k for k in recon if k not in inst]
    return set_, drop


def _tile(nodes, by_parent, occ):
    """Outermost chrome landmark whose STRUCTURAL subtree key recurs (occ>=2), non-overlapping.
    Returns [(subtree_key, root_node), ...]; does not descend into a selected tile (no double-count)."""
    selected, stack = [], list(_roots(nodes))
    while stack:
        n = stack.pop()
        if n.get("aria_role") in CHROME:
            k = _subtree(n, by_parent)
            if occ[k] >= 2:
                selected.append((k, n))
                continue
        stack.extend(by_parent.get(n["id"], []))
    return selected


def _emit_order(root, by_parent):
    """Template node order: pre-order DFS, children in emit order. Defines the re-base offsets so an
    instance only needs ONE base id; node i's id = id_base + i."""
    out, stack = [], [root]
    while stack:
        n = stack.pop()
        out.append(n)
        stack.extend(reversed(by_parent.get(n["id"], [])))
    return out


def dedup_chrome(route_skeletons):
    """route_skeletons: {route_id: [node, ...]}. Returns the deduped artifact:
      {templates: {key: [<full template node>, ...]},   # one node list per recurring structural key
       routes:    {route_id: {refs:[{template, id_base, root_parent, nodes:[{bbox, vdelta}...],
                                      exceptions:{str(i):{field:value}}, drop:{str(i):[field,...]}}],
                              donor_keys:[<key whose ONE full copy this route holds>],
                              rest:[<non-deduped nodes>]}}}
    The donor route (first instance of a key) stores NO ref and NO full chrome copy of its own — its
    chrome IS templates[key], recovered verbatim via donor_keys. So each template is stored exactly
    once; only the m-1 non-donor instances become refs (and count as saved). Lossless: reconstruct()."""
    prepared = {rid: (nodes, _children(nodes)) for rid, nodes in route_skeletons.items()}
    occ = Counter()
    for nodes, bp in prepared.values():
        for n in nodes:
            if n.get("aria_role") in CHROME:
                occ[_subtree(n, bp)] += 1

    templates = {}
    routes_out = {}
    for rid, (nodes, bp) in prepared.items():
        tiles = _tile(nodes, bp, occ)
        tiled_ids = set()
        refs = []
        donor_keys = []                                   # keys whose ONE full copy this route holds
        for key, root in tiles:
            order = _emit_order(root, bp)
            tiled_ids.update(n["id"] for n in order)
            if key not in templates:                      # first instance = template (donor)
                templates[key] = [dict(n) for n in order]
                donor_keys.append(key)                    # recovered verbatim from templates[key]
                continue
            tmpl_nodes = templates[key]
            # Equal structural keys must mean equal subtree size; a length mismatch would imply a
            # key collision and silently truncate `zip` below (a latent loss). Fail loud instead.
            assert len(tmpl_nodes) == len(order), \
                "structural-key collision: template/instance subtree length mismatch"
            base = root["id"]
            tmpl_idx = {tn["id"]: j for j, tn in enumerate(tmpl_nodes)}   # template id -> emit index
            per_node, exceptions, drops = [], {}, {}
            # Siblings must share emit order (DOM pre-order, stable across a site's routes) for the
            # bbox-only ideal; a reordered instance stays lossless but charges id exceptions.
            # Re-basing: web_skeleton numbers nodes id=len(emitted) in pre-order, so a tiled landmark
            # (a COMPLETE subtree) occupies a contiguous id range -> node i sits at base+i, and an
            # internal node's parent sits at base+(template-parent's emit index). The tile root's
            # parent points OUTSIDE the tile -> stored verbatim as root_parent. Simulate the exact
            # ship-path reconstruction (via _reconstruct_node), then diff it against the real instance:
            # every differing/instance-only field becomes a charged exception and every template-only
            # field a drop -> lossless by construction (subsumes id/parent/z/confidence + any unkeyed
            # field, both presence directions).
            for i, (tn, inode) in enumerate(zip(tmpl_nodes, order)):
                vdelta = _encode_volatile(tn, inode)
                exp_id = base + i
                exp_parent = root.get("parent") if i == 0 else base + tmpl_idx[tn["parent"]]
                has_bbox = inode.get("bbox") is not None
                recon = _reconstruct_node(tn, exp_id, exp_parent, inode.get("bbox"), has_bbox, vdelta)
                # vdelta and the exception patch may BOTH touch token_ref by design: vdelta encodes
                # the volatile leaves cheaply, and _node_patch charges the whole token_ref only if recon
                # still differs (extra subkeys / presence). Keep both — collapsing one path reintroduces loss.
                set_, drop = _node_patch(recon, inode)
                per_node.append({"bbox": inode.get("bbox"), "vdelta": vdelta})
                if set_:
                    exceptions[str(i)] = set_               # str key: JSON-stable, charged, lossless
                if drop:
                    drops[str(i)] = drop                   # template-only fields to delete on rebuild
            refs.append({"template": key, "id_base": base,
                         "root_parent": root.get("parent"),
                         "nodes": per_node, "exceptions": exceptions, "drop": drops})
        rest = [n for n in nodes if n["id"] not in tiled_ids]
        routes_out[rid] = {"refs": refs, "donor_keys": donor_keys, "rest": rest}
    return {"templates": templates, "routes": routes_out}


def reconstruct(artifact):
    """Inverse of dedup_chrome: returns {route_id: [node, ...]} node-set identical (id-keyed) to the
    input — node ORDER is not part of the contract (downstream compares by id, e.g. Task 5's
    _node_sets_equal). A donor_key's chrome is templates[key] emitted verbatim (its nodes already
    carry the donor's original id/parent/bbox/volatile — no re-basing). Each ref is expanded from its
    template with re-based ids, per-node bbox + volatile delta, charged exceptions, and drops
(template-only fields removed so an instance that lacks a template field does not inherit it)."""
    templates = artifact["templates"]
    out = {}
    for rid, route in artifact["routes"].items():
        nodes = []
        for key in route.get("donor_keys", []):           # the route that holds this template in full
            nodes.extend(copy.deepcopy(n) for n in templates[key])
        for ref in route["refs"]:
            tmpl = templates[ref["template"]]
            base = ref["id_base"]
            id_of = [base + i for i in range(len(tmpl))]
            # map a template node's original id -> its emit-order index, to re-base parent links
            tmpl_idx = {tn["id"]: i for i, tn in enumerate(tmpl)}
            for i, tn in enumerate(tmpl):
                # _reconstruct_node DEEP-copies the template (so _apply_volatile's in-place setdefault
                # never aliases the shared template / serialized artifact across instances), re-bases
                # id/parent, overrides bbox, and applies the volatile delta — the SAME builder the
                # dedup side simulated against, so the charged patch lands on the exact ship path.
                pn = ref["nodes"][i]
                new_parent = ref.get("root_parent") if i == 0 else id_of[tmpl_idx[tn["parent"]]]
                has_bbox = pn.get("bbox") is not None
                n = _reconstruct_node(tn, id_of[i], new_parent, pn.get("bbox"), has_bbox, pn["vdelta"])
                for f, v in ref.get("exceptions", {}).get(str(i), {}).items():
                    n[f] = v                                  # restore charged field exactly (str key)
                for f in ref.get("drop", {}).get(str(i), []):
                    n.pop(f, None)                            # delete template-only field
                nodes.append(n)
        nodes.extend(copy.deepcopy(n) for n in route["rest"])
        out[rid] = nodes
    return out
