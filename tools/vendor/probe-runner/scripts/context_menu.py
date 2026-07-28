#!/usr/bin/env python3
"""Right-click in window then select an item from the resulting context menu.

Usage:
  context_menu.py <owner> <x> <y> "<item label>"
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    p.add_argument("item", help="visible label of the menu item to click")
    args = p.parse_args()

    cliclick = which_or_die("cliclick", "brew install cliclick")
    win = resolve_window(args.owner)
    gx = win["bounds"]["x"] + args.x
    gy = win["bounds"]["y"] + args.y
    run([cliclick, f"rc:{gx},{gy}"])
    time.sleep(0.15)
    script = f'''
tell application "System Events"
    tell process "{args.owner}"
        click menu item "{args.item}" of menu 1 of window 1
    end tell
end tell
'''
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode != 0:
        stderr = (r.stderr or "").strip()
        die(
            f"context_menu: item '{args.item}' not found in {args.owner}'s "
            f"context menu (osascript rc={r.returncode}{': ' + stderr if stderr else ''})",
            code=r.returncode or 2,
        )
    print(json.dumps({"item": args.item}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
