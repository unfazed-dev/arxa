#!/usr/bin/env python3
"""Hot reload (optionally force-reload) the attached Flutter isolate.

Usage:
  flutter_reload.py            # reloadSources
  flutter_reload.py --restart  # reloadSources force=true (closest VM-service
                               # equivalent to hot restart; true hot restart
                               # requires the flutter_tool process).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--restart", action="store_true")
    args = p.parse_args()

    try:
        iso = first_isolate()
        if args.restart:
            result = rpc("reloadSources", {"force": True, "pause": False}, isolate=iso)
            method = "reloadSources(force=true)"
        else:
            result = rpc("reloadSources", isolate=iso)
            method = "reloadSources"
        emit_json({"method": method, "result": result})
    except Exception as e:
        die(str(e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
