#!/usr/bin/env python3
"""Best-effort gesture synthesis.

True multi-touch gestures on macOS require private APIs that aren't
reliably callable from Python. This script falls back to coarse
keyboard/scroll equivalents.

Usage:
  gesture.py <owner> --pinch in|out --magnitude N
  gesture.py <owner> --swipe up|down|left|right
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--pinch", choices=["in", "out"])
    p.add_argument("--swipe", choices=["up", "down", "left", "right"])
    p.add_argument("--magnitude", type=int, default=200)
    args = p.parse_args()

    try:
        import Quartz  # type: ignore
    except ImportError:
        die("missing Quartz. pip3 install pyobjc-framework-Quartz")

    win = resolve_window(args.owner)
    cx = win["bounds"]["x"] + win["bounds"]["w"] // 2
    cy = win["bounds"]["y"] + win["bounds"]["h"] // 2
    cliclick = which_or_die("cliclick", "brew install cliclick")
    run([cliclick, f"m:{cx},{cy}"])
    time.sleep(0.05)

    if args.pinch:
        # Cmd + scroll = zoom in many apps. Approximate pinch.
        # Hold cmd-down, send scroll, release cmd.
        cmd_down = Quartz.CGEventCreateKeyboardEvent(None, 55, True)  # type: ignore  # 55 = cmd
        cmd_up = Quartz.CGEventCreateKeyboardEvent(None, 55, False)  # type: ignore
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_down)  # type: ignore
        dy = args.magnitude if args.pinch == "out" else -args.magnitude
        ev = Quartz.CGEventCreateScrollWheelEvent(None, 0, 2, dy, 0)  # type: ignore
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)  # type: ignore
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_up)  # type: ignore
        print(json.dumps({"pinch": args.pinch, "magnitude": args.magnitude}, ensure_ascii=False, separators=(",", ":")))
        return 0

    if args.swipe:
        dx = {"up": 0, "down": 0, "left": -args.magnitude, "right": args.magnitude}[args.swipe]
        dy = {"up": args.magnitude, "down": -args.magnitude, "left": 0, "right": 0}[args.swipe]
        ev = Quartz.CGEventCreateScrollWheelEvent(None, 0, 2, dy, dx)  # type: ignore
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)  # type: ignore
        print(json.dumps({"swipe": args.swipe, "magnitude": args.magnitude}, ensure_ascii=False, separators=(",", ":")))
        return 0

    die("must pass --pinch or --swipe")
    return 2


if __name__ == "__main__":
    sys.exit(main())
