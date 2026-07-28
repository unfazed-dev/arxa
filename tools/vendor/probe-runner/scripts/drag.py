#!/usr/bin/env python3
"""Drag inside a window: press at A, move to B, release.

Usage:
  drag.py <owner> --from X1,Y1 --to X2,Y2 [--duration MS]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, which_or_die


def parse_xy(s: str) -> tuple[int, int]:
    parts = s.split(",")
    if len(parts) != 2:
        die("expected X,Y")
    return int(parts[0]), int(parts[1])


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--from", dest="frm", required=True)
    p.add_argument("--to", required=True)
    p.add_argument("--duration", type=int, default=200, help="wait ms between down and up")
    p.add_argument("--abs", dest="abs_", action="store_true")
    args = p.parse_args()

    cliclick = which_or_die("cliclick", "brew install cliclick")
    x1, y1 = parse_xy(args.frm)
    x2, y2 = parse_xy(args.to)

    if not args.abs_:
        win = resolve_window(args.owner)
        ox, oy = win["bounds"]["x"], win["bounds"]["y"]
        x1 += ox; y1 += oy; x2 += ox; y2 += oy

    run([cliclick, f"dd:{x1},{y1}"])
    time.sleep(args.duration / 2000.0)
    run([cliclick, f"m:{x2},{y2}"])
    time.sleep(args.duration / 2000.0)
    run([cliclick, f"du:{x2},{y2}"])

    print(json.dumps({"from": [x1, y1], "to": [x2, y2]}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
