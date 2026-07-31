#!/usr/bin/env python3
"""Screenshot the connected Android device via `adb exec-out screencap -p`."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_path, out_path


def main() -> int:
    argparse.ArgumentParser(description="Screenshot the connected Android device.").parse_args()
    o = out_path("android", "png")
    with open(o, "wb") as f:
        adb_cmd(["exec-out", "screencap", "-p"], stdout=f)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
