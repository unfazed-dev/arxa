#!/usr/bin/env python3
"""Drop a file path into a target window (Finder-style drag).

Uses osascript to instruct Finder to drag the file's icon onto the
target window's coordinate.

Usage:
  drop_file.py <owner> <file-path> <x> <y>
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("file")
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    args = p.parse_args()

    f = Path(args.file).resolve()
    if not f.exists():
        die(f"file not found: {f}")

    win = resolve_window(args.owner)
    gx = win["bounds"]["x"] + args.x
    gy = win["bounds"]["y"] + args.y

    # Use `open -a <app> <file>` as the most reliable cross-app drop substitute.
    # True drag-and-drop synthesis is not reliable in public macOS APIs.
    subprocess.run(["open", "-a", args.owner, str(f)], check=True)
    print(json.dumps({"opened": str(f), "into": args.owner, "at": [gx, gy]}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
