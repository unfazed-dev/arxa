#!/usr/bin/env python3
"""Wait until a window with the given owner name appears or vanishes.

Usage:
  wait_window.py <owner> [--state appear|disappear] [--timeout SEC] [--interval SEC]
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, resolve_window


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--state", choices=["appear", "disappear"], default="appear")
    p.add_argument("--timeout", type=float, default=30.0)
    p.add_argument("--interval", type=float, default=0.25)
    args = p.parse_args()

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            matches = resolve_window(args.owner, all_=True)
        except SystemExit:
            matches = []
        present = bool(matches)
        if args.state == "appear" and present:
            emit_json(matches[0] if matches else {})
            return 0
        if args.state == "disappear" and not present:
            print(f'{{"owner":"{args.owner}","state":"disappeared"}}')
            return 0
        time.sleep(args.interval)

    die(f"timeout waiting for '{args.owner}' to {args.state}", code=124)
    return 124  # unreachable


if __name__ == "__main__":
    sys.exit(main())
