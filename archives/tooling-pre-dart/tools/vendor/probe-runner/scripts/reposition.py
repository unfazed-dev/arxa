#!/usr/bin/env python3
"""Move and/or resize an app window.

Usage:
  reposition.py <owner> --pos X,Y              # move only
  reposition.py <owner> --size WxH             # resize only
  reposition.py <owner> --pos X,Y --size WxH   # both
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window  # noqa


def _ascript(owner: str, body: str) -> None:
    script = f'''
tell application "System Events"
    tell process "{owner}"
        {body}
    end tell
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--pos")
    p.add_argument("--size")
    args = p.parse_args()

    if not args.pos and not args.size:
        die("pass --pos and/or --size")

    body_lines = []
    if args.pos:
        x, y = args.pos.split(",")
        body_lines.append(f"set position of window 1 to {{{int(x)}, {int(y)}}}")
    if args.size:
        w, h = args.size.lower().split("x")
        body_lines.append(f"set size of window 1 to {{{int(w)}, {int(h)}}}")

    _ascript(args.owner, "\n        ".join(body_lines))
    print(f'{{"owner":"{args.owner}","pos":"{args.pos}","size":"{args.size}"}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
