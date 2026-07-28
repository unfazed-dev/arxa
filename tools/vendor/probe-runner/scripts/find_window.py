#!/usr/bin/env python3
"""Resolve a macOS app's window(s) by owner name.

Usage:
  find_window.py <owner-name>            # default: print first/largest match as JSON
  find_window.py <owner-name> --all      # print every match
  find_window.py <owner-name> --index 1  # nth match (0-based, largest-first)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_json, resolve_window


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", help="macOS window owner name (e.g. 'perf_domain_heavy_100')")
    p.add_argument("--all", dest="all_", action="store_true")
    p.add_argument("--index", type=int, default=0)
    args = p.parse_args()

    res = resolve_window(args.owner, index=args.index, all_=args.all_)
    emit_json(res)
    return 0


if __name__ == "__main__":
    sys.exit(main())
