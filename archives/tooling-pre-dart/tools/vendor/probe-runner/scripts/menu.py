#!/usr/bin/env python3
"""Click a menu-bar item by path.

Usage:
  menu.py <owner> "File/Open…"
  menu.py <owner> "Window/Bring All to Front"
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("path", help='slash-separated, e.g. "File/Open…"')
    args = p.parse_args()

    parts = args.path.split("/")
    if len(parts) < 2:
        print('path needs Menu/Item form', file=sys.stderr)
        return 2

    # Build nested AppleScript click of menu item path.
    top = parts[0]
    rest = parts[1:]
    nested = " ".join(f'of menu "{p}" of menu item "{p}"' for p in rest[:-1])
    final = rest[-1]
    script = f'''
tell application "{args.owner}" to activate
tell application "System Events"
    tell process "{args.owner}"
        click menu item "{final}" {nested} of menu "{top}" of menu bar 1
    end tell
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True)
    print(f'{{"clicked":"{args.path}"}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
