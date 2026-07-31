#!/usr/bin/env python3
"""Swipe on Android via `adb shell input swipe`.

Usage:
  adb_swipe.py <x1> <y1> <x2> <y2> [--duration-ms MS]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("x1", type=int); p.add_argument("y1", type=int)
    p.add_argument("x2", type=int); p.add_argument("y2", type=int)
    p.add_argument("--duration-ms", type=int, default=300)
    args = p.parse_args()
    adb_cmd(["shell", "input", "swipe",
             str(args.x1), str(args.y1), str(args.x2), str(args.y2), str(args.duration_ms)])
    emit_json({"from": [args.x1, args.y1], "to": [args.x2, args.y2], "ms": args.duration_ms})
    return 0


if __name__ == "__main__":
    sys.exit(main())
