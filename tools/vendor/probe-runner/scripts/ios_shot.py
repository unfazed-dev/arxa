#!/usr/bin/env python3
"""Screenshot the booted iOS sim."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, out_path


def main() -> int:
    argparse.ArgumentParser(description="Screenshot the booted iOS sim.").parse_args()
    o = out_path("ios", "png")
    r = subprocess.run(
        ["xcrun", "simctl", "io", "booted", "screenshot", str(o)],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl screenshot failed (no booted sim?): {r.stderr.strip()}",
            code=r.returncode or 2)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
