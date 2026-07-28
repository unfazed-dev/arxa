#!/usr/bin/env python3
"""Click in a window at window-relative or absolute coords.

Usage:
  click.py <owner> <x> <y>                  # left single click, window-relative
  click.py <owner> <x> <y> --double         # left double click
  click.py <owner> <x> <y> --triple         # left triple click
  click.py <owner> <x> <y> --right          # right click
  click.py <owner> <x> <y> --hold MS        # down, sleep MS ms, up
  click.py --abs X Y                        # absolute screen coords
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, tcc_check, which_or_die
from _platform import assert_desktop_input


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("x", type=int, nargs="?")
    p.add_argument("y", type=int, nargs="?")
    p.add_argument("--abs", dest="abs_", action="store_true")
    p.add_argument("--double", action="store_true")
    p.add_argument("--triple", action="store_true")
    p.add_argument("--right", action="store_true")
    p.add_argument("--hold", type=int, help="hold MS milliseconds between down and up")
    args = p.parse_args()

    if args.x is None or args.y is None:
        die("x and y required")

    assert_desktop_input("click")         # macOS-only (cliclick); clear error on Linux/Win
    tcc_check("accessibility")
    cliclick = which_or_die("cliclick", "brew install cliclick")

    if args.abs_:
        gx, gy = args.x, args.y
    else:
        if not args.owner:
            die("owner required unless --abs is set")
        win = resolve_window(args.owner)
        gx = win["bounds"]["x"] + args.x
        gy = win["bounds"]["y"] + args.y

    if args.hold is not None:
        run([cliclick, f"dd:{gx},{gy}"])
        time.sleep(args.hold / 1000.0)
        run([cliclick, f"du:{gx},{gy}"])
    elif args.right:
        run([cliclick, f"rc:{gx},{gy}"])
    elif args.triple:
        run([cliclick, f"tc:{gx},{gy}"])
    elif args.double:
        run([cliclick, f"dc:{gx},{gy}"])
    else:
        run([cliclick, f"c:{gx},{gy}"])

    print(json.dumps({"x": gx, "y": gy}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
