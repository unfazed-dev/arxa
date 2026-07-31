#!/usr/bin/env python3
"""Best-effort: open Safari's Develop menu → <app> → Web Inspector.

For wry/Tauri/Dioxus desktop apps on macOS. Requires:
- "Show Develop menu" enabled in Safari → Settings → Advanced
- "Allow remote automation" enabled if you also want safaridriver later
- The target wry app launched with devtools available (default in debug,
  or `with_disable_context_menu(false)` / `devtools` Cargo feature)

Usage:
  safari_inspect.py <owner>          # try to open inspector for first webview
  safari_inspect.py --list           # list inspectable apps under Develop
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die  # noqa


LIST_SCRIPT = r'''
tell application "Safari" to activate
delay 0.2
tell application "System Events"
    tell process "Safari"
        set developMenu to menu "Develop" of menu bar 1
        set itemNames to name of every menu item of developMenu
    end tell
end tell
return itemNames
'''


def _click_inspector(owner: str) -> None:
    script = f'''
tell application "Safari" to activate
delay 0.2
tell application "System Events"
    tell process "Safari"
        set developMenu to menu "Develop" of menu bar 1
        click menu item "{owner}" of developMenu
        delay 0.2
        try
            click menu item 1 of menu "{owner}" of developMenu
        end try
    end tell
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--list", dest="list_", action="store_true")
    args = p.parse_args()

    if args.list_:
        r = subprocess.run(["osascript", "-e", LIST_SCRIPT], check=True, capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        return 0

    if not args.owner:
        die("owner or --list required")
    _click_inspector(args.owner)
    print(f'{{"opened":"{args.owner}"}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
