#!/usr/bin/env python3
"""Read AX text/value for an element matched by identifier or label.

Usage:
  ax_text.py <owner> --id <AXIdentifier>
  ax_text.py <owner> --label <substring of AXTitle/AXDescription>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, resolve_window


def _walk(elem, want, axApi):
    role = _attr(elem, "AXRole", axApi)
    ident = _attr(elem, "AXIdentifier", axApi)
    title = _attr(elem, "AXTitle", axApi)
    label = _attr(elem, "AXDescription", axApi)

    if want.get("id") and str(ident or "") == want["id"]:
        return elem
    if want.get("label"):
        substr = want["label"]
        if substr.lower() in str(title or "").lower() or substr.lower() in str(label or "").lower():
            return elem

    children = _attr(elem, "AXChildren", axApi) or []
    for c in children:
        try:
            r = _walk(c, want, axApi)
            if r is not None:
                return r
        except Exception:  # noqa: BLE001
            continue
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
    found = _walk(app, {"id": args.id, "label": args.label}, ax)
    if found is None:
        die("not found")
    val = _attr(found, "AXValue", ax) or _attr(found, "AXTitle", ax)
    emit_json({"value": str(val) if val is not None else None})
    return 0


if __name__ == "__main__":
    sys.exit(main())
