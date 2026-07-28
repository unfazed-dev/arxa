#!/usr/bin/env python3
"""_theme — pure core for Regime-3a theme/preference style-delta capture (no
browser, no I/O). web_skeleton wraps these with CDP Emulation.setEmulatedMedia
recapture. The join key is backendNodeId (DOMSnapshot-stable across a base->
condition recapture; verified, design §1) — NOT the positional skeleton id.
Deterministic; unit-tested. Content-free: emits raw resolved values that
bundle_writer redacts via _style.redact_theme before disk."""


def styles_by_backend(recs):
    """Map backendNodeId -> full resolved style dict, for ELEMENT records only
    (skip pseudo-element records and records with no backendNodeId). recs is
    web_skeleton.parse_snapshot output."""
    out = {}
    for r in recs:
        if r.get("pseudo"):
            continue
        b = r.get("backend")
        if b is None:
            continue
        out[b] = r.get("style") or {}
    return out


def diff_theme(base_by_backend, cond_by_backend, universe):
    """Return {backendNodeId: {prop: cond_value}} for every node present in BOTH
    base and the condition where a prop in `universe` differs. A node absent from
    the condition capture (display:none under the condition, or a theme-triggered
    DOM mutation) is DROPPED — never reattached (style-only ceiling, design §9).
    computedStyles resolves every requested prop for a laid-out node, so both raw
    maps carry every prop; the compare is a plain `base != cond`, which catches
    both directions (a reset is just a value change). Emits nothing for a node
    with no changed prop."""
    out = {}
    for b, base_style in base_by_backend.items():
        cond_style = cond_by_backend.get(b)
        if cond_style is None:
            continue
        delta = {}
        for prop in universe:
            if base_style.get(prop) != cond_style.get(prop):
                delta[prop] = cond_style.get(prop)
        if delta:
            out[b] = delta
    return out


def rekey_by_node_id(delta_by_backend, node_backend):
    """Re-key {backendNodeId: delta} -> {node_id: delta} via node_backend
    ({node_id: backendNodeId}). A backendNodeId with no matching node_id is
    dropped (defensive)."""
    backend_to_id = {b: nid for nid, b in node_backend.items()}
    out = {}
    for b, delta in delta_by_backend.items():
        nid = backend_to_id.get(b)
        if nid is not None:
            out[nid] = delta
    return out


def build_node_theme(per_condition):
    """Transpose {condition_label: {node_id: delta}} -> {node_id: {label: delta}},
    keeping only non-empty deltas. The on-disk _node_theme sidecar shape."""
    out = {}
    for label, by_node in per_condition.items():
        for nid, delta in by_node.items():
            if delta:
                out.setdefault(nid, {})[label] = delta
    return out
