#!/usr/bin/env python3
"""Minimize, zoom (maximize), close, or unminimize a window.

Usage:
  window_state.py <owner> minimize|zoom|close|unminimize|fullscreen
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die  # noqa


SCRIPTS = {
    "minimize": '''tell application "System Events" to tell process "{owner}" to set value of attribute "AXMinimized" of window 1 to true''',
    "unminimize": '''tell application "System Events" to tell process "{owner}" to set value of attribute "AXMinimized" of window 1 to false''',
    "zoom": '''tell application "System Events" to tell process "{owner}" to click button 2 of window 1''',  # green = zoom on most apps
    "close": '''tell application "System Events" to tell process "{owner}" to click button 1 of window 1''',
    "fullscreen": '''tell application "System Events" to tell process "{owner}" to set value of attribute "AXFullScreen" of window 1 to true''',
}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("action", choices=list(SCRIPTS))
    args = p.parse_args()

    subprocess.run(["osascript", "-e", SCRIPTS[args.action].format(owner=args.owner)], check=True)
    print(f'{{"owner":"{args.owner}","action":"{args.action}"}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
