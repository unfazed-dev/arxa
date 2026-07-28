#!/usr/bin/env python3
"""Record a video of a window or full screen.

Usage:
  record.py <owner> --seconds N        # fixed-length window video (screencapture -V)
  record.py <owner> --start            # start recording in background (writes pid file)
  record.py <owner> --stop             # stop the running recording
  record.py <owner> --seconds N --clicks --audio
  record.py <owner> --full --seconds N
  record.py <owner> --ffmpeg --seconds N   # use ffmpeg avfoundation for lossless
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
from _common import OUTDIR, die, emit_path, out_path, resolve_window, run, tcc_check, which_or_die

PID_FILE = OUTDIR / "record.pid"


def _spawn(cmd: list[str], out: Path) -> int:
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    PID_FILE.write_text(f"{proc.pid}\n{out}\n")
    return proc.pid


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--seconds", type=int)
    p.add_argument("--start", action="store_true")
    p.add_argument("--stop", action="store_true")
    p.add_argument("--full", action="store_true")
    p.add_argument("--clicks", action="store_true")
    p.add_argument("--audio", action="store_true")
    p.add_argument("--cursor", action="store_true")
    p.add_argument("--ffmpeg", action="store_true")
    p.add_argument("--out")
    args = p.parse_args()

    if args.stop:
        if not PID_FILE.exists():
            die("no active recording")
        pid_str, *rest = PID_FILE.read_text().splitlines()
        pid = int(pid_str)
        try:
            os.kill(pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        time.sleep(1.0)
        PID_FILE.unlink(missing_ok=True)
        if rest:
            print(rest[0])
        return 0

    if not args.owner:
        die("owner required (unless --stop)")

    tcc_check("screen_recording")
    o = Path(args.out) if args.out else out_path(args.owner, "mov")

    if args.ffmpeg:
        ff = which_or_die("ffmpeg", "brew install ffmpeg")
        cmd = [ff, "-y", "-f", "avfoundation", "-i", "1:none"]
        if args.seconds:
            cmd += ["-t", str(args.seconds)]
        cmd.append(str(o.with_suffix(".mp4")))
        if args.start:
            pid = _spawn(cmd, o.with_suffix(".mp4"))
            print(f'{{"pid":{pid},"out":"{o.with_suffix(".mp4")}"}}')
            return 0
        run(cmd)
        emit_path(o.with_suffix(".mp4"))
        return 0

    cap = which_or_die("screencapture", "bundled with macOS")
    cmd = [cap, "-x"]
    if args.clicks:
        cmd.append("-k")
    if args.audio:
        cmd.append("-g")
    if args.cursor:
        cmd.append("-C")
    if not args.full:
        win = resolve_window(args.owner)
        cmd += ["-l", str(win["window_id"])]
    if args.seconds and not args.start:
        cmd += ["-V", str(args.seconds)]
    else:
        cmd.append("-v")
    cmd.append(str(o))

    if args.start:
        pid = _spawn(cmd, o)
        print(f'{{"pid":{pid},"out":"{o}"}}')
        return 0

    run(cmd)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
