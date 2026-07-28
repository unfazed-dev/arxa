#!/usr/bin/env python3
"""Dump Flutter widget / render / layer / semantics tree.

The `render`/`layer`/`semantics` kinds return a human-readable TEXT DUMP (the
output of the Flutter `debugDump*Tree` RPCs), useful for eyeballing the tree
but NOT structured geometry. For per-element screen RECTS in a machine-readable
probe-skeleton/2 schema (bbox/role/parent, skeleton_diff-compatible), use
`flutter_skeleton.py` instead — it walks every RenderBox over the VM service
and reads `localToGlobal` + `size`. The `widget` kind returns structured
DiagnosticsNode JSON (topology + descriptions, but no bboxes).

Usage:
  flutter_tree.py [--kind widget|render|layer|semantics]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


KIND_METHOD = {
    "widget": "ext.flutter.inspector.getRootWidgetSummaryTree",
    "widget-full": "ext.flutter.inspector.getRootWidget",
    "render": "ext.flutter.debugDumpRenderTree",
    "layer": "ext.flutter.debugDumpLayerTree",
    "semantics": "ext.flutter.debugDumpSemanticsTreeInTraversalOrder",
}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--kind", default="widget", choices=list(KIND_METHOD))
    args = p.parse_args()

    try:
        iso = first_isolate()
        params = {}
        if args.kind in ("widget", "widget-full"):
            params["objectGroup"] = "probe-runner"
        result = rpc(KIND_METHOD[args.kind], params=params, isolate=iso)
        emit_json(result)
    except Exception as e:
        die(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
