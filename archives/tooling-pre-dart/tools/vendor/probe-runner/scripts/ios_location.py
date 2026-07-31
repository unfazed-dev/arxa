#!/usr/bin/env python3
"""Set GPS location on the booted iOS sim.

Usage:
  ios_location.py <lat> <lon>
  ios_location.py clear
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


def main() -> int:
    # Either `clear` (1 token) or `<lat> <lon>` (2 tokens); argparse handles
    # -h and the "at least one arg" check, the mode split branches below.
    # Negative coords (e.g. -33.0) parse as positionals: argparse treats
    # negative-number-looking tokens as positionals when no option resembles one.
    p = argparse.ArgumentParser(description="Set GPS location on the booted iOS sim.")
    p.add_argument("rest", nargs="+")
    rest = p.parse_args().rest

    if len(rest) == 1 and rest[0] == "clear":
        r = subprocess.run(
            ["xcrun", "simctl", "location", "booted", "clear"],
            check=False, capture_output=True, text=True,
        )
        if r.returncode != 0:
            die(f"simctl location clear failed: {r.stderr.strip() or r.stdout.strip()}",
                code=r.returncode or 2)
        emit_json({"cleared": True})
        return 0
    if len(rest) != 2:
        die("usage: ios_location.py <lat> <lon> | clear")
    lat, lon = rest
    r = subprocess.run(
        ["xcrun", "simctl", "location", "booted", "set", f"{lat},{lon}"],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl location set failed: {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"lat": float(lat), "lon": float(lon)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
