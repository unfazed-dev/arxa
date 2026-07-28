#!/usr/bin/env python3
"""Stream iOS sim log via idb.

The stream handle comes from _ios.idb_popen, so a missing companion /
unpinned target auto-recovers (idb connect + one respawn) instead of dying
on a raw Popen traceback. Pin a target with PROBE_RUNNER_IOS_UDID when more
than one simulator is booted.

Usage:
  ios_log.py [--seconds N]
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_popen


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int, default=0)
    args = p.parse_args()
    proc = idb_popen(["log"])
    deadline = time.monotonic() + args.seconds if args.seconds else None
    try:
        while proc.stdout:
            if deadline and time.monotonic() > deadline:
                proc.terminate()
                break
            line = proc.stdout.readline()
            if not line:
                break
            sys.stdout.write(line)
            sys.stdout.flush()
    except KeyboardInterrupt:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
