#!/usr/bin/env python3
"""Record video of the booted iOS sim.

Usage:
  ios_record.py --seconds N
  ios_record.py --start                 # background; pid written to record.pid
  ios_record.py --stop
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import OUTDIR, die, emit_path, out_path

PID_FILE = OUTDIR / "ios_record.pid"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int)
    p.add_argument("--start", action="store_true")
    p.add_argument("--stop", action="store_true")
    args = p.parse_args()

    if args.stop:
        if not PID_FILE.exists():
            die("no active iOS recording")
        pid_str, *rest = PID_FILE.read_text().splitlines()
        try:
            os.kill(int(pid_str), signal.SIGINT)
        except ProcessLookupError:
            pass
        time.sleep(1.0)
        PID_FILE.unlink(missing_ok=True)
        if rest:
            print(rest[0])
        return 0

    o = out_path("ios", "mp4")
    cmd = ["xcrun", "simctl", "io", "booted", "recordVideo", str(o)]

    if args.start:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        PID_FILE.write_text(f"{proc.pid}\n{o}\n")
        print(f'{{"pid":{proc.pid},"out":"{o}"}}')
        return 0

    if args.seconds:
        proc = subprocess.Popen(cmd)
        time.sleep(args.seconds)
        proc.send_signal(signal.SIGINT)
        proc.wait()
    else:
        subprocess.run(cmd)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
