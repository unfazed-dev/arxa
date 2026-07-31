#!/usr/bin/env python3
"""Activate / raise / focus an app's window.

Usage:
  focus.py <owner>
  focus.py <owner> --bundle-id com.example.app   # activate by bundle id
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die  # noqa


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--bundle-id", dest="bundle_id")
    args = p.parse_args()

    if args.bundle_id:
        subprocess.run(["open", "-b", args.bundle_id], check=True)
    else:
        if not args.owner:
            die("owner or --bundle-id required")
        subprocess.run(
            ["osascript", "-e", f'tell application "{args.owner}" to activate'],
            check=True,
        )

    print(json.dumps({"focused": args.bundle_id or args.owner}, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
