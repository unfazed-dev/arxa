# slots.py
#!/usr/bin/env python3
"""slots — the typed placeholder-slot schema the rebuilding agent fills.
One slot per content node (image/text/svg); mechanism nodes get none. Emits a
slots manifest {slots:[...], index:[node_id,...]} consumed by bundle_writer."""
from __future__ import annotations

import content_firewall as cf


def _aspect(b):
    return round(b["w"] / b["h"], 4) if b.get("h") else None


def _char_bucket(n):
    if n <= 24:
        return "short"
    if n <= 120:
        return "medium"
    return "long"


def _fill_hint(kind, node, info):
    if kind == "image":
        return f"{info.get('role','image')} image, aspect {_aspect(node['bbox'])}"
    if kind == "text":
        return f"{_char_bucket(node.get('text_len') or 0)} text"
    if kind == "svg":
        return f"{info.get('svg_class','svg')} svg ({'swap' if info.get('svg_class') in ('logo','illustration') else 'keep'})"
    return kind


def _slot(node, kind, info):
    b = node["bbox"]
    s = {
        "id": node["id"], "type": kind,
        "box": b, "aspect_ratio": _aspect(b),
        "theme_ref": node.get("token_ref"),
        "anim_ref": node.get("anim_ref"),
        "fill_hint": _fill_hint(kind, node, info),
    }
    if kind == "text":
        s["text_class"] = {"char_len_bucket": _char_bucket(node.get("text_len") or 0)}
    if kind == "svg":
        s["svg_class"] = info.get("svg_class")
    return s


def build_slots(nodes):
    """Return {'slots': [Slot,...], 'index': [node_id,...]} for every content or
    kept-content node. Mechanism nodes contribute nothing."""
    out = []
    for n in nodes:
        info = cf.classify_node(n)
        if info["klass"] == "mechanism":
            continue
        out.append(_slot(n, info["type"], info))
    return {"slots": out, "index": [s["id"] for s in out]}
