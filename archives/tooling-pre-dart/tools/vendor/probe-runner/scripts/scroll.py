#!/usr/bin/env python3
"""Synthesize mouse-wheel / trackpad scroll events at the current cursor or
in a target window.

Usage:
  scroll.py <owner> <dx> <dy>            # focus window, scroll
  scroll.py <owner> <dx> <dy> --at X Y   # hover at X,Y in window then scroll
  scroll.py --abs <dx> <dy>              # just scroll at current cursor
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("dx", type=int)
    p.add_argument("dy", type=int)
    p.add_argument("--at", nargs=2, type=int, metavar=("X", "Y"))
    p.add_argument("--abs", dest="abs_", action="store_true")
    args = p.parse_args()

    try:
        import Quartz  # type: ignore
    except ImportError:
        die("missing Quartz (pyobjc). pip3 install pyobjc-framework-Quartz")

    if not args.abs_:
        if not args.owner:
            die("owner required unless --abs is set")
        win = resolve_window(args.owner)
        if args.at:
            cliclick = which_or_die("cliclick", "brew install cliclick")
            gx = win["bounds"]["x"] + args.at[0]
            gy = win["bounds"]["y"] + args.at[1]
            run([cliclick, f"m:{gx},{gy}"])

    # kCGScrollEventUnitPixel = 0, kCGScrollEventUnitLine = 1
    ev = Quartz.CGEventCreateScrollWheelEvent(None, 0, 2, int(args.dy), int(args.dx))  # type: ignore
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)  # type: ignore
    print(f'{{"dx":{args.dx},"dy":{args.dy}}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
