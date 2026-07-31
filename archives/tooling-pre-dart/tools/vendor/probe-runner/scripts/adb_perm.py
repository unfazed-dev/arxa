#!/usr/bin/env python3
"""Grant / revoke a runtime permission on Android.

Usage:
  adb_perm.py grant <pkg> <android.permission.NAME>
  adb_perm.py revoke <pkg> <android.permission.NAME>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Grant or revoke a runtime permission.")
    p.add_argument("action", choices=["grant", "revoke"])
    p.add_argument("pkg")
    p.add_argument("perm", help="full permission name, e.g. android.permission.CAMERA")
    args = p.parse_args()
    adb_cmd(["shell", "pm", args.action, args.pkg, args.perm])
    emit_json({"action": args.action, "pkg": args.pkg, "perm": args.perm})
    return 0


if __name__ == "__main__":
    sys.exit(main())
