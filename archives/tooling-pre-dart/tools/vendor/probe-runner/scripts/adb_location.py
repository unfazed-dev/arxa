#!/usr/bin/env python3
"""Set emulator GPS location.

Usage:
  adb_location.py <lat> <lon>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Set emulator GPS location.")
    p.add_argument("lat", type=float)
    p.add_argument("lon", type=float)
    args = p.parse_args()
    # emulator console expects lon,lat order
    adb_cmd(["emu", "geo", "fix", str(args.lon), str(args.lat)])
    emit_json({"lat": args.lat, "lon": args.lon})
    return 0


if __name__ == "__main__":
    sys.exit(main())
