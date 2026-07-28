#!/usr/bin/env python3
"""Override status bar fields on the booted sim (e.g. time, battery).

Usage:
  ios_status_bar.py override --time "9:41" --batteryState charged --batteryLevel 100
  ios_status_bar.py clear
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["override", "clear"])
    p.add_argument("--time")
    p.add_argument("--batteryState")
    p.add_argument("--batteryLevel", type=int)
    p.add_argument("--cellularBars", type=int)
    p.add_argument("--operatorName")
    p.add_argument("--wifiBars", type=int)
    args = p.parse_args()

    if args.action == "clear":
        subprocess.run(["xcrun", "simctl", "status_bar", "booted", "clear"], check=True)
        emit_json({"cleared": True})
        return 0

    cmd = ["xcrun", "simctl", "status_bar", "booted", "override"]
    for k in ("time", "batteryState", "batteryLevel", "cellularBars", "operatorName", "wifiBars"):
        v = getattr(args, k)
        if v is not None:
            cmd.extend([f"--{k}", str(v)])
    subprocess.run(cmd, check=True)
    emit_json({"override": cmd[5:]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
