#!/usr/bin/env python3
"""Swipe from x1,y1 to x2,y2 on the booted iOS sim.

Usage:
  ios_swipe.py <x1> <y1> <x2> <y2> [--duration SEC]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_run
from _common import emit_json, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("x1", type=int); p.add_argument("y1", type=int)
    p.add_argument("x2", type=int); p.add_argument("y2", type=int)
    p.add_argument("--duration", type=float, default=0.3)
    args = p.parse_args()
    idb_run(["ui", "swipe",
        str(args.x1), str(args.y1), str(args.x2), str(args.y2),
        "--duration", str(args.duration),], capture=True)
    emit_json({"from": [args.x1, args.y1], "to": [args.x2, args.y2]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
