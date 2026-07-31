#!/usr/bin/env python3
"""Burst-capture N stills at a target fps.

Usage:
  multishot.py <owner> --count N --fps F [--out-dir DIR]
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import OUTDIR, emit_json, out_path, resolve_window, run, tcc_check, ts, which_or_die


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--count", type=int, required=True)
    p.add_argument("--fps", type=float, default=30.0)
    p.add_argument("--out-dir", dest="out_dir")
    args = p.parse_args()

    tcc_check("screen_recording")
    cap = which_or_die("screencapture", "bundled with macOS")
    win = resolve_window(args.owner)
    interval = 1.0 / args.fps

    sub = Path(args.out_dir) if args.out_dir else OUTDIR / f"{args.owner}-{ts()}-burst"
    sub.mkdir(parents=True, exist_ok=True)

    paths = []
    for i in range(args.count):
        f = sub / f"frame_{i:06d}.png"
        start = time.monotonic()
        run([cap, "-x", "-l", str(win["window_id"]), str(f)])
        paths.append(str(f))
        delay = interval - (time.monotonic() - start)
        if delay > 0:
            time.sleep(delay)

    emit_json({"dir": str(sub), "count": len(paths), "fps": args.fps, "frames": paths})
    return 0


if __name__ == "__main__":
    sys.exit(main())
