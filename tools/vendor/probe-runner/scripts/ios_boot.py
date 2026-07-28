#!/usr/bin/env python3
"""Boot, shutdown, or erase an iOS simulator.

Usage:
  ios_boot.py "<name|udid>" [--shutdown|--erase]
  ios_boot.py --booted        # noop, just print current booted device
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


def _udid_from_name(name: str) -> str:
    r = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"],
                       check=True, capture_output=True, text=True)
    data = json.loads(r.stdout)
    for runtime, devs in data.get("devices", {}).items():
        for d in devs:
            if d.get("name") == name or d.get("udid") == name:
                return d["udid"]
    die(f"no sim named '{name}'")
    return ""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("device", nargs="?")
    p.add_argument("--shutdown", action="store_true")
    p.add_argument("--erase", action="store_true")
    p.add_argument("--booted", action="store_true")
    args = p.parse_args()

    if args.booted:
        r = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted", "--json"],
            check=True, capture_output=True, text=True,
        )
        emit_json(json.loads(r.stdout))
        return 0

    if not args.device:
        die("device name or UDID required")
    udid = _udid_from_name(args.device)

    if args.shutdown:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True)
    elif args.erase:
        subprocess.run(["xcrun", "simctl", "erase", udid], check=True)
    else:
        subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
        subprocess.run(["open", "-a", "Simulator"], check=False)

    emit_json({"udid": udid, "action": "shutdown" if args.shutdown else "erase" if args.erase else "boot"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
