#!/usr/bin/env python3
"""Tail logcat scoped to a package's pid.

Usage:
  adb_log.py <pkg> [--seconds N]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_bin, serial
from _common import die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("pkg")
    p.add_argument("--seconds", type=int, default=0)
    args = p.parse_args()
    # Soft pidof — `pidof X` exits rc=1 when no match, which adb_shell
    # would treat as "device/emulator booted?" via _adb.adb_shell's
    # sys.exit path. Use a direct subprocess so we can phrase the
    # message in terms of the actual failure mode (no such pkg).
    base = [adb_bin()]
    s = serial()
    if s:
        base += ["-s", s]
    r = subprocess.run(
        base + ["shell", f"pidof {args.pkg}"],
        capture_output=True, text=True, check=False,
    )
    pid = (r.stdout or "").strip()
    if not pid:
        die(
            f"no process matching pkg '{args.pkg}' on device "
            f"(check: adb devices && adb shell pm list packages | grep {args.pkg})"
        )
    proc = subprocess.Popen([adb_bin(), "logcat", f"--pid={pid}"], stdout=subprocess.PIPE, text=True)
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
