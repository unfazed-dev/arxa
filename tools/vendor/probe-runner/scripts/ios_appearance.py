#!/usr/bin/env python3
"""Set light/dark appearance on the booted sim.

Usage:
  ios_appearance.py light|dark
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_appearance.py", description=__doc__)
    p.add_argument("mode", choices=("light", "dark"))
    args = p.parse_args()
    r = subprocess.run(
        ["xcrun", "simctl", "ui", "booted", "appearance", args.mode],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl appearance failed (no booted sim?): {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"appearance": args.mode})
    return 0


if __name__ == "__main__":
    sys.exit(main())
