#!/usr/bin/env python3
"""Dump the macOS accessibility tree of an app as JSON.

Usage:
  ax_tree.py <owner>                    # full tree, depth-limited
  ax_tree.py <owner> --max-depth 10
  ax_tree.py <owner> --pid <PID>        # bypass owner lookup
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, resolve_window, tcc_check


def _walk(elem, depth: int, max_depth: int, axApi) -> dict:
    role = _attr(elem, "AXRole", axApi)
    title = _attr(elem, "AXTitle", axApi)
    label = _attr(elem, "AXDescription", axApi)
    value = _attr(elem, "AXValue", axApi)
    ident = _attr(elem, "AXIdentifier", axApi)
    enabled = _attr(elem, "AXEnabled", axApi)
    pos = _attr(elem, "AXPosition", axApi)
    size = _attr(elem, "AXSize", axApi)

    node = {
        "role": str(role) if role else None,
        "title": str(title) if title else None,
        "label": str(label) if label else None,
        "value": str(value) if value is not None else None,
        "id": str(ident) if ident else None,
        "enabled": bool(enabled) if enabled is not None else None,
        "position": _xy(pos),
        "size": _wh(size),
        "children": [],
    }

    if depth >= max_depth:
        return node

    children = _attr(elem, "AXChildren", axApi) or []
    for c in children:
        try:
            node["children"].append(_walk(c, depth + 1, max_depth, axApi))
        except Exception as e:  # noqa: BLE001
            node["children"].append({"error": str(e)})
    return node


def _attr(elem, name: str, axApi):
    err, val = axApi.AXUIElementCopyAttributeValue(elem, name, None)  # type: ignore
    if err:
        return None
    return val


def _xy(pos):
    if pos is None:
        return None
    try:
        return {"x": float(pos.x), "y": float(pos.y)}
    except Exception:  # noqa: BLE001
        return str(pos)


def _wh(size):
    if size is None:
        return None
    try:
        return {"w": float(size.width), "h": float(size.height)}
    except Exception:  # noqa: BLE001
        return str(size)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--pid", type=int)
    p.add_argument("--max-depth", type=int, default=8)
    args = p.parse_args()

    try:
        import ApplicationServices as ax  # type: ignore
    except ImportError:
        die("missing pyobjc ApplicationServices. pip3 install pyobjc-framework-ApplicationServices")
        return 2

    tcc_check("accessibility")

    if args.pid is None:
        if not args.owner:
            die("owner or --pid required")
        win = resolve_window(args.owner)
        pid = win["pid"]
    else:
        pid = args.pid

    app = ax.AXUIElementCreateApplication(pid)  # type: ignore
    tree = _walk(app, 0, args.max_depth, ax)
    emit_json({"pid": pid, "tree": tree})
    return 0


if __name__ == "__main__":
    sys.exit(main())
