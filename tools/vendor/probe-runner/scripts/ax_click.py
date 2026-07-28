#!/usr/bin/env python3
"""Click an element by AX identifier or label (no coords required).

Usage:
  ax_click.py <owner> --id <AXIdentifier>
  ax_click.py <owner> --label <substring>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, resolve_window


def _walk(elem, want, axApi):
    ident = _attr(elem, "AXIdentifier", axApi)
    title = _attr(elem, "AXTitle", axApi)
    label = _attr(elem, "AXDescription", axApi)

    if want.get("id") and str(ident or "") == want["id"]:
        return elem
    if want.get("label"):
        substr = want["label"].lower()
        if substr in str(title or "").lower() or substr in str(label or "").lower():
            return elem

    children = _attr(elem, "AXChildren", axApi) or []
    for c in children:
        r = _walk(c, want, axApi)
        if r is not None:
            return r
    return None


def _attr(elem, name: str, axApi):
    err, val = axApi.AXUIElementCopyAttributeValue(elem, name, None)  # type: ignore
    if err:
        return None
    return val


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--id")
    p.add_argument("--label")
    args = p.parse_args()

    if not args.id and not args.label:
        die("pass --id or --label")

    try:
        import ApplicationServices as ax  # type: ignore
    except ImportError:
        die("missing pyobjc ApplicationServices")
        return 2

    win = resolve_window(args.owner)
    app = ax.AXUIElementCreateApplication(win["pid"])  # type: ignore
    target = _walk(app, {"id": args.id, "label": args.label}, ax)
    if target is None:
        die("not found")
    err = ax.AXUIElementPerformAction(target, "AXPress")  # type: ignore
    if err:
        die(f"AXPress failed: {err}")
    emit_json({"clicked": args.id or args.label})
    return 0


if __name__ == "__main__":
    sys.exit(main())
