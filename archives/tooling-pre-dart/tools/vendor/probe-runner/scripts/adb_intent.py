#!/usr/bin/env python3
"""Broadcast an Android intent to simulate a notification or system event.

Usage:
  adb_intent.py "<action>" [--component pkg/.Receiver] [--extra k=v ...]

Note: this script invokes `am broadcast`. For file push/pull, see adb_files.py.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Broadcast an Android intent (am broadcast).")
    p.add_argument("action", help="intent action, e.g. com.example.MY_EVENT")
    p.add_argument("--component", help="target receiver, e.g. com.example/.MyReceiver")
    p.add_argument("--extra", action="append", default=[], help="k=v (string extra), repeatable")
    args = p.parse_args()

    cmd = ["shell", "am", "broadcast", "-a", args.action]
    if args.component:
        cmd += ["-n", args.component]
    for e in args.extra:
        k, v = e.split("=", 1)
        cmd += ["--es", k, v]
    adb_cmd(cmd)
    emit_json({"broadcast": args.action, "component": args.component, "extras": args.extra})
    return 0


if __name__ == "__main__":
    sys.exit(main())
