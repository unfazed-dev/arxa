#!/usr/bin/env python3
"""Type text into the focused field on the iOS sim.

Usage:
  ios_type.py "<text>"
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_run
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_type.py", description=__doc__)
    p.add_argument("text")
    args = p.parse_args()
    subprocess.run(["idb", "ui", "text", args.text], check=True)
    emit_json({"typed": len(args.text)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
