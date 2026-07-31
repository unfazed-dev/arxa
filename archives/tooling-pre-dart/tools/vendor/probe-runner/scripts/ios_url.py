#!/usr/bin/env python3
"""Open a URL / deep link in the booted iOS sim.

Usage:
  ios_url.py <url>
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json  # noqa


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_url.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("url", help="URL or deep link to open in the booted sim")
    args = p.parse_args()

    r = subprocess.run(
        ["xcrun", "simctl", "openurl", "booted", args.url],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl openurl failed (no booted sim?): {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"opened": args.url})
    return 0


if __name__ == "__main__":
    sys.exit(main())
