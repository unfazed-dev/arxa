#!/usr/bin/env python3
"""Manage Android apps via adb.

Usage:
  adb_app.py install <apk>
  adb_app.py uninstall <pkg>
  adb_app.py launch <pkg>[/<.Activity>]
  adb_app.py force-stop <pkg>
  adb_app.py list                          # third-party packages
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd, adb_shell
from _common import die, emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Manage Android apps via adb.")
    p.add_argument("verb", choices=["install", "uninstall", "launch", "force-stop", "list"])
    p.add_argument("arg", nargs="?", help="apk path / package name; omit for 'list'")
    args = p.parse_args()

    if args.verb == "list":
        out = adb_shell("pm list packages -3")
        sys.stdout.write(out)
        return 0

    if not args.arg:
        die(f"{args.verb} requires an argument")

    if args.verb == "install":
        adb_cmd(["install", "-r", args.arg])
        emit_json({"installed": args.arg})
    elif args.verb == "uninstall":
        adb_cmd(["uninstall", args.arg])
        emit_json({"uninstalled": args.arg})
    elif args.verb == "launch":
        if "/" in args.arg:
            adb_cmd(["shell", "am", "start", "-n", args.arg])
        else:
            adb_cmd(["shell", "monkey", "-p", args.arg, "-c", "android.intent.category.LAUNCHER", "1"])
        emit_json({"launched": args.arg})
    elif args.verb == "force-stop":
        adb_cmd(["shell", "am", "force-stop", args.arg])
        emit_json({"stopped": args.arg})
    return 0


if __name__ == "__main__":
    sys.exit(main())
