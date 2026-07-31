#!/usr/bin/env python3
"""derisk_screencapturekit — LIVE validation that the ScreenCaptureKit bridge
captures a real window identically (or better) to the legacy screencapture CLI.

NOT collected by pytest (derisk_* convention). The SCK capture path
(_sck.capture_window_still) is exercised here against a live window; the pure
detection logic is unit-tested in test_platform.py. Run this by hand when
changing _sck.py or targeting a new macOS version.

RECIPE (macOS 12.3+ with pyobjc-framework-ScreenCaptureKit + Screen Recording granted):
  1. open any GUI app whose window owner name you know (e.g. 'Safari', 'Code')
  2. python3 derisk_screencapturekit.py <owner>

It captures the same window via ScreenCaptureKit AND the legacy screencapture
CLI, then compares the two PNGs' dimensions + a mean-RGB diff (they won't be
pixel-identical due to cursor/timing, but dimensions must match and the diff
must be small). Emits a JSON verdict.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path, resolve_window, run, which_or_die
from _platform import has_screencapturekit


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 0
    owner = sys.argv[1]

    if not has_screencapturekit():
        die("ScreenCaptureKit unavailable (need macOS 12.3+ + "
            "pyobjc-framework-ScreenCaptureKit + Screen Recording permission).")

    win = resolve_window(owner)
    wid = win["window_id"]

    # 1. ScreenCaptureKit path
    from _sck import capture_window_still
    sck_png = out_path("derisk-sck", "png")
    try:
        capture_window_still(wid, str(sck_png))
    except (ImportError, RuntimeError) as e:
        die("ScreenCaptureKit capture failed: %s" % e)

    # 2. legacy CLI path
    cap = which_or_die("screencapture", "bundled with macOS")
    cli_png = out_path("derisk-cli", "png")
    run([cap, "-x", "-l", str(wid), str(cli_png)])

    # 3. compare dimensions + mean-RGB diff
    from PIL import Image, ImageChops, ImageStat
    a = Image.open(sck_png).convert("RGB")
    b = Image.open(cli_png).convert("RGB")
    dim_match = a.size == b.size
    if dim_match:
        diff = ImageChops.difference(a, b)
        stat = ImageStat.Stat(diff)
        mean = sum(stat.mean) / len(stat.mean)
        score = mean / 255.0
    else:
        score = None

    ok = dim_match and (score is None or score < 0.05)
    emit_json({
        "derisk": "screencapturekit", "owner": owner, "window_id": wid,
        "sck_png": str(sck_png), "cli_png": str(cli_png),
        "sck_size": a.size, "cli_size": b.size, "dimensions_match": dim_match,
        "mean_rgb_diff_score": score,
        "ok": ok,
        "note": ("dimensions match + diff < 5%" if ok else
                 "dimensions differ or diff >= 5% — investigate cursor/timing"),
    })
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
