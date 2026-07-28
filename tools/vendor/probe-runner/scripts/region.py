#!/usr/bin/env python3
"""Capture a rectangular region of the screen (or window-relative).

Usage:
  region.py --rect X,Y,W,H                    # absolute screen coords
  region.py <owner> --rect X,Y,W,H            # relative to window origin
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, out_path, resolve_window, run, tcc_check, which_or_die


def parse_rect(s: str) -> tuple[int, int, int, int]:
    parts = s.split(",")
    if len(parts) != 4:
        die("rect must be X,Y,W,H")
    return tuple(int(p) for p in parts)  # type: ignore


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--rect", required=True)
    p.add_argument("--out")
    args = p.parse_args()

    tcc_check("screen_recording")
    cap = which_or_die("screencapture", "bundled with macOS")
    x, y, w, h = parse_rect(args.rect)

    if args.owner:
        win = resolve_window(args.owner)
        x += win["bounds"]["x"]
        y += win["bounds"]["y"]

    o = Path(args.out) if args.out else out_path(args.owner or "screen", "png", kind="region")
    cmd = [cap, "-x", "-R", f"{x},{y},{w},{h}", str(o)]
    run(cmd)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
