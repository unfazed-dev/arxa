#!/usr/bin/env python3
"""web_vectors — OPT-IN vtracer raster->SVG REFERENCE traces (non-certified,
IP-clean) for role:svg nodes. Slots ship from the skeleton already; this verb
only fills vec/<id>.svg + flips the slot vec_ref. Pure crop/filter funcs are
unit-tested; the vtracer (Python API) + screenshot I/O in main() is
live-validated."""
from __future__ import annotations

import argparse
import base64
import json
import os
import tempfile
from pathlib import Path

import vtracer

from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args


def crop_rect(node, dpr):
    """Convert a node's CSS-px bbox to device-px crop rect for a dpr screenshot."""
    b = node["bbox"]
    return {"left": int(round(b["x"] * dpr)), "top": int(round(b["y"] * dpr)),
            "width": int(round(b["w"] * dpr)), "height": int(round(b["h"] * dpr))}


def svg_nodes(nodes):
    return [n for n in nodes if n.get("role") == "svg"]


def _vtracer(in_png, out_svg):
    """Raster->SVG via the vtracer Python library (no CLI binary exists).
    Returns True on success, False on any tracing error."""
    try:
        vtracer.convert_image_to_svg_py(in_png, out_svg)
        return True
    except Exception:
        return False


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--skeleton", required=True, help="skeleton.json (for svg nodes)")
    p.add_argument("--bundle", required=True, help="bundle dir to write vec/ + update manifest")
    add_transport_args(p)
    args = p.parse_args()

    skeleton = json.loads(Path(args.skeleton).read_text())
    targets = svg_nodes(skeleton["nodes"])
    if not targets:
        emit_json({"ok": True, "traced": 0, "note": "no svg nodes"})
        return 0

    engine, ev, device = resolve_web_eval(args)
    if not hasattr(ev, "sess"):
        die("web_vectors needs a CDP transport for clipped screenshots.")
    try:
        navigate(ev, engine, args.url)
        dpr = ev.ev("devicePixelRatio")

        vec_dir = Path(args.bundle) / "assets" / "vec"
        vec_dir.mkdir(parents=True, exist_ok=True)
        traced = []
        for n in targets:
            rect = crop_rect(n, dpr)
            shot = ev.sess.send("Page.captureScreenshot", {
                "format": "png", "clip": {"x": rect["left"] / dpr, "y": rect["top"] / dpr,
                "width": rect["width"] / dpr, "height": rect["height"] / dpr, "scale": 1}})
            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
                tmp.write(base64.b64decode(shot["data"]))
                png_path = tmp.name
            svg_path = str(vec_dir / f"{n['id']}.svg")
            try:
                if _vtracer(png_path, svg_path):
                    traced.append(n["id"])
            finally:
                try:
                    os.unlink(png_path)  # don't leave one temp PNG per svg node
                except OSError:
                    pass
    finally:
        ev.close()

    # flip vec_ref on the matching manifest slots
    man_path = Path(args.bundle) / "assets" / "manifest.json"
    if man_path.exists():
        man = json.loads(man_path.read_text())
        for s in man.get("slots", []):
            if s.get("kind") == "svg" and s["node_id"] in traced:
                s["vec_ref"] = f"vec/{s['node_id']}.svg"
        man_path.write_text(json.dumps(man, indent=2))

    emit_json({"ok": True, "traced": len(traced), "ids": traced})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
