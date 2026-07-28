#!/usr/bin/env python3
"""Manage apps on the booted iOS simulator.

Usage:
  ios_app.py install <path/to/App.app|.ipa>
  ios_app.py uninstall <bundle-id>
  ios_app.py launch <bundle-id> [-- arg1 arg2 ...]
  ios_app.py terminate <bundle-id>
  ios_app.py list
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json  # noqa


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_app.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="verb", required=True)

    sub.add_parser("list", help="list apps installed on the booted sim")

    s_install = sub.add_parser("install", help="install an .app or .ipa")
    s_install.add_argument("path")

    s_uninstall = sub.add_parser("uninstall", help="uninstall by bundle id")
    s_uninstall.add_argument("bundle_id")

    s_launch = sub.add_parser("launch", help="launch a bundle id with optional argv")
    s_launch.add_argument("bundle_id")
    s_launch.add_argument("argv", nargs=argparse.REMAINDER,
                          help="passed to the app after '--'")

    s_terminate = sub.add_parser("terminate", help="terminate a running bundle id")
    s_terminate.add_argument("bundle_id")

    args = p.parse_args()
    verb = args.verb

    if verb == "list":
        r = subprocess.run(
            ["xcrun", "simctl", "listapps", "booted"],
            check=False, capture_output=True, text=True,
        )
        if r.returncode != 0:
            die(f"simctl listapps failed (no booted sim?): {r.stderr.strip()}",
                code=r.returncode or 2)
        sys.stdout.write(r.stdout)
        return 0

    if verb == "install":
        cmd = ["xcrun", "simctl", "install", "booted", args.path]
        arg = args.path
    elif verb == "uninstall":
        cmd = ["xcrun", "simctl", "uninstall", "booted", args.bundle_id]
        arg = args.bundle_id
    elif verb == "launch":
        extra = args.argv or []
        if extra and extra[0] == "--":
            extra = extra[1:]
        cmd = ["xcrun", "simctl", "launch", "booted", args.bundle_id, *extra]
        arg = args.bundle_id
    elif verb == "terminate":
        cmd = ["xcrun", "simctl", "terminate", "booted", args.bundle_id]
        arg = args.bundle_id
    else:
        die(f"unknown verb '{verb}'")
        return 2

    r = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"simctl {verb} failed: {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"verb": verb, "arg": arg, "stdout": r.stdout.strip()})
    return 0


if __name__ == "__main__":
    sys.exit(main())
