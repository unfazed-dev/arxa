#!/usr/bin/env python3
"""Move the cursor without clicking.

Usage:
  hover.py <owner> <x> <y>          # window-relative
  hover.py --abs X Y                # absolute
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("x", type=int, nargs="?")
    p.add_argument("y", type=int, nargs="?")
    p.add_argument("--abs", dest="abs_", action="store_true")
    args = p.parse_args()

    if args.x is None or args.y is None:
        die("x and y required")

    cliclick = which_or_die("cliclick", "brew install cliclick")
    if args.abs_:
        gx, gy = args.x, args.y
    else:
        if not args.owner:
            die("owner required unless --abs is set")
        win = resolve_window(args.owner)
        gx = win["bounds"]["x"] + args.x
        gy = win["bounds"]["y"] + args.y

    run([cliclick, f"m:{gx},{gy}"])
    print(json.dumps({"x": gx, "y": gy}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
