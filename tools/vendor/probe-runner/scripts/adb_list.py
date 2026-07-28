#!/usr/bin/env python3
"""List attached Android devices / emulators."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_bin


def main() -> int:
    argparse.ArgumentParser(description="List attached Android devices / emulators.").parse_args()
    r = subprocess.run([adb_bin(), "devices", "-l"], check=True, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
