#!/usr/bin/env python3
"""Set system settings on the connected device.

Usage:
  adb_settings.py darkmode on|off
  adb_settings.py set <namespace> <key> <value>     # ns: system|secure|global
  adb_settings.py get <namespace> <key>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd, adb_shell
from _common import die, emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Read / write Android Settings.Global/System/Secure.")
    sub = p.add_subparsers(dest="verb", required=True)

    pd = sub.add_parser("darkmode", help="toggle UI night mode")
    pd.add_argument("mode", choices=["on", "off"])

    ps = sub.add_parser("set", help="settings put <ns> <key> <value>")
    ps.add_argument("namespace", choices=["system", "secure", "global"])
    ps.add_argument("key")
    ps.add_argument("value")

    pg = sub.add_parser("get", help="settings get <ns> <key>")
    pg.add_argument("namespace", choices=["system", "secure", "global"])
    pg.add_argument("key")

    args = p.parse_args()

    if args.verb == "darkmode":
        adb_cmd(["shell", "cmd", "uimode", "night", "yes" if args.mode == "on" else "no"])
        emit_json({"darkmode": args.mode})
        return 0
    if args.verb == "set":
        adb_cmd(["shell", "settings", "put", args.namespace, args.key, args.value])
        emit_json({"set": [args.namespace, args.key, args.value]})
        return 0
    if args.verb == "get":
        v = adb_shell(f"settings get {args.namespace} {args.key}").strip()
        emit_json({"value": v})
        return 0
    die("unknown verb")
    return 2


if __name__ == "__main__":
    sys.exit(main())
