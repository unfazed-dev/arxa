#!/usr/bin/env python3
"""Record video of the device screen and pull it.

Usage:
  adb_record.py --seconds N
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_path, out_path


def main() -> int:
    p = argparse.ArgumentParser(description="Record video of the device screen and pull it.")
    p.add_argument("--seconds", type=int, default=10)
    args = p.parse_args()
    remote = "/sdcard/probe-runner.mp4"
    adb_cmd(["shell", "screenrecord", "--time-limit", str(args.seconds), remote])
    o = out_path("android", "mp4")
    adb_cmd(["pull", remote, str(o)], stderr=subprocess.DEVNULL)
    adb_cmd(["shell", "rm", "-f", remote], check=False)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
