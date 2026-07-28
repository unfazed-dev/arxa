#!/usr/bin/env python3
"""Locate a Flutter widget by key, type, or rendered text.

Usage:
  flutter_find.py --key <Key.value>
  flutter_find.py --type FloatingActionButton
  flutter_find.py --text "Sign in"
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


def _walk(node: dict, want: dict) -> list[dict]:
    matches = []
    desc = node.get("description") or ""
    # The widget type lives in `widgetRuntimeType` (e.g. "AdaptiveButton"), NOT the
    # node `type` field (which is the DiagnosticsNode kind like "_ElementDiagnosticableTreeNode").
    rt = node.get("widgetRuntimeType") or ""
    if want.get("type") and want["type"] in (rt, desc):
        matches.append(node)
    if want.get("key") and want["key"] in desc:
        matches.append(node)
    # Text match: a Text widget's description carries its rendered data (e.g.
    # "Continue with Google"); also matches the type name as a type-alias. Note: text
    # rendered NATIVELY (a LiquidGlassButton's label passed to the platform view) does
    # NOT appear as a Flutter Text node — for those, locate by --type instead.
    if want.get("text") and want["text"] in desc:
        matches.append(node)
    for c in node.get("children") or []:
        matches.extend(_walk(c, want))
    return matches


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--key")
    p.add_argument("--type")
    p.add_argument("--text")
    args = p.parse_args()

    if not any([args.key, args.type, args.text]):
        die("pass --key, --type, or --text")

    try:
        iso = first_isolate()
        tree = rpc("ext.flutter.inspector.getRootWidgetSummaryTree",
                   {"objectGroup": "probe-runner"}, isolate=iso)
        result = (tree or {}).get("result")
        root = result if isinstance(result, dict) else tree
        matches = _walk(root, {"key": args.key, "type": args.type, "text": args.text})
        emit_json({"count": len(matches), "matches": matches})
    except Exception as e:
        die(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
