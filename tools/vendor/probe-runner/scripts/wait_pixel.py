#!/usr/bin/env python3
"""Wait until a region of the screen changes (poll + hash diff).

Captures a baseline region screenshot, then polls every `--interval`
seconds until either:
  - the region's PNG bytes differ from the baseline (success, rc=0), or
  - `--timeout` seconds elapse (rc=124 — matches the deadline convention).

`--rect x,y,w,h` is in global screen coordinates by default. When an
`owner` is provided, x,y are interpreted relative to that window's
top-left and translated to global coords via Quartz.

The optional `--threshold N` lets noisy anti-aliasing slide: only count
the region as changed when at least N PNG bytes differ from the
baseline. Default 0 (any difference = changed).

Usage:
  wait_pixel.py --rect 100,100,200,80 --timeout 5
  wait_pixel.py TextEdit --rect 0,0,200,80 --timeout 5 --interval 0.25
  wait_pixel.py --rect 100,100,200,80 --timeout 5 --threshold 64
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import OUTDIR, die, emit_json, resolve_window, ts


def _shot(rect: tuple[int, int, int, int], dest: Path) -> None:
    x, y, w, h = rect
    r = subprocess.run(
        ["screencapture", "-x", "-t", "png", "-R", f"{x},{y},{w},{h}", str(dest)],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0 or not dest.exists() or dest.stat().st_size == 0:
        die(f"screencapture failed: {(r.stderr or '').strip() or 'empty output'}",
            code=r.returncode or 2)


def _hash(p: Path) -> tuple[str, bytes]:
    data = p.read_bytes()
    return hashlib.md5(data).hexdigest(), data


def _byte_diff(a: bytes, b: bytes) -> int:
    n = min(len(a), len(b))
    diff = abs(len(a) - len(b))
    for i in range(n):
        if a[i] != b[i]:
            diff += 1
    return diff


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner", nargs="?")
    p.add_argument("--rect", required=True, help="x,y,w,h (window-relative if owner; else global)")
    p.add_argument("--timeout", type=float, default=10.0)
    p.add_argument("--interval", type=float, default=0.5)
    p.add_argument("--threshold", type=int, default=0,
                   help="N differing PNG bytes required to count as changed (default 0)")
    args = p.parse_args()

    try:
        parts = [int(v.strip()) for v in args.rect.split(",")]
    except ValueError:
        die("rect must be x,y,w,h (four integers)")
    if len(parts) != 4:
        die("rect must be x,y,w,h (four integers)")
    x, y, w, h = parts

    if args.owner:
        win = resolve_window(args.owner)
        x += win["bounds"]["x"]
        y += win["bounds"]["y"]

    rect = (x, y, w, h)
    stamp = ts()
    base = OUTDIR / f"wait_pixel-{stamp}-base.png"
    _shot(rect, base)
    base_hash, base_bytes = _hash(base)

    deadline = time.monotonic() + args.timeout
    samples = 1
    cur = OUTDIR / f"wait_pixel-{stamp}-cur.png"
    while time.monotonic() < deadline:
        time.sleep(args.interval)
        _shot(rect, cur)
        samples += 1
        cur_hash, cur_bytes = _hash(cur)
        if cur_hash == base_hash:
            continue
        if args.threshold > 0 and _byte_diff(base_bytes, cur_bytes) < args.threshold:
            continue
        emit_json({
            "changed": True,
            "elapsed_s": round(time.monotonic() - (deadline - args.timeout), 3),
            "samples": samples,
            "baseline": str(base),
            "final": str(cur),
        })
        return 0

    emit_json({
        "changed": False,
        "elapsed_s": args.timeout,
        "samples": samples,
        "baseline": str(base),
    })
    return 124


if __name__ == "__main__":
    sys.exit(main())
