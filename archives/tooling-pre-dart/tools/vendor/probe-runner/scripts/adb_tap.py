#!/usr/bin/env python3
"""Tap at x,y on Android via `adb shell input tap`."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Tap at x,y on Android.")
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    args = p.parse_args()
    adb_cmd(["shell", "input", "tap", str(args.x), str(args.y)])
    emit_json({"x": args.x, "y": args.y})
    return 0


if __name__ == "__main__":
    sys.exit(main())
