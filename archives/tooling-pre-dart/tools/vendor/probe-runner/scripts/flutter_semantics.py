#!/usr/bin/env python3
"""Toggle Flutter SemanticsBinding so OS AX trees populate.

Usage:
  flutter_semantics.py enable|disable
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


def main() -> int:
    p = argparse.ArgumentParser(prog="flutter_semantics.py", description=__doc__)
    p.add_argument("mode", choices=("enable", "disable"))
    args = p.parse_args()
    on = args.mode == "enable"
    flag = "true" if on else "false"
    try:
        iso = first_isolate()
        # String service extension — `enabled` must be the string "true"/"false";
        # a JSON bool causes the extension to never reply.
        r = rpc("ext.flutter.inspector.show", {"enabled": flag}, isolate=iso)
    except RuntimeError as e:
        die(str(e))
    emit_json({"semantics": "on" if on else "off", "result": r})
    return 0


if __name__ == "__main__":
    sys.exit(main())
