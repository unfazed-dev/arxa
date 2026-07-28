#!/usr/bin/env python3
"""Tail unified system log filtered to a process.

Usage:
  tail_log.py <owner> [--seconds N] [--level info|debug|default]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import iter_lines_until, resolve_window


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--seconds", type=int, default=0)
    p.add_argument("--level", default="default")
    args = p.parse_args()

    win = resolve_window(args.owner)
    cmd = [
        "log", "stream",
        "--style", "compact",
        "--level", args.level,
        "--predicate", f'processIdentifier == {win["pid"]}',
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
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
