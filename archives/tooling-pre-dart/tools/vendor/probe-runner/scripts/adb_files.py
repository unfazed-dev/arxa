#!/usr/bin/env python3
"""Push or pull files to/from an Android device.

Usage:
  adb_files.py push <local> <remote>
  adb_files.py pull <remote> <local>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Push or pull files to/from an Android device.")
    p.add_argument("verb", choices=["push", "pull"])
    p.add_argument("a", help="push: <local>  | pull: <remote>")
    p.add_argument("b", help="push: <remote> | pull: <local>")
    args = p.parse_args()
    adb_cmd([args.verb, args.a, args.b])
    emit_json({"verb": args.verb, "a": args.a, "b": args.b})
    return 0


if __name__ == "__main__":
    sys.exit(main())
