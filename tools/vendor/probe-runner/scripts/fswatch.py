#!/usr/bin/env python3
"""Stream filesystem change events for one or more paths.

Usage:
  fswatch.py <path> [<path>...] [--seconds N]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import iter_lines_until, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("paths", nargs="+")
    p.add_argument("--seconds", type=int, default=0, help="0 = run until interrupted")
    args = p.parse_args()

    which_or_die("fswatch", "brew install fswatch")
    proc = subprocess.Popen(["fswatch", "-x", *args.paths], stdout=subprocess.PIPE)
    deadline = time.monotonic() + args.seconds if args.seconds else None
    try:
        for line in iter_lines_until(proc, deadline=deadline):
            sys.stdout.write(line)
            sys.stdout.flush()
    except KeyboardInterrupt:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
