#!/usr/bin/env python3
"""Capture a still PNG of a window (or whole screen).

Usage:
  shot.py <owner>                  # window-id capture
  shot.py <owner> --full           # entire main display
  shot.py <owner> --all-displays   # one shot per display
  shot.py <owner> --cursor         # include cursor (-C)
  shot.py <owner> --no-shadow      # drop window drop shadow (-o)
  shot.py <owner> --out PATH       # explicit output path
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import emit_path, out_path, resolve_window, run, tcc_check, which_or_die
from _platform import assert_desktop_capture, has_screencapturekit


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--full", action="store_true")
    p.add_argument("--all-displays", dest="all_displays", action="store_true")
    p.add_argument("--cursor", action="store_true")
    p.add_argument("--no-shadow", dest="no_shadow", action="store_true")
    p.add_argument("--out")
    args = p.parse_args()

    assert_desktop_capture("shot")        # macOS-only desktop capture; clear error on Linux/Win
    tcc_check("screen_recording")
    cap = which_or_die("screencapture", "bundled with macOS")

    if args.all_displays:
        outs: list[Path] = []
        for i in range(1, 5):
            o = Path(args.out) if args.out else out_path(args.owner, "png", kind=f"d{i}")
            cmd = [cap, "-x", "-D", str(i)]
            if args.cursor:
                cmd.append("-C")
            cmd.append(str(o))
            run(cmd, check=False)
            if o.exists() and o.stat().st_size > 0:
                outs.append(o)
        for o in outs:
            emit_path(o)
        return 0

    o = Path(args.out) if args.out else out_path(args.owner, "png")

    # Prefer ScreenCaptureKit (zero-copy GPU, lower latency) for single-window
    # stills when available; fall back to the legacy `screencapture` CLI for
    # --full / --all-displays / older macOS / missing binding. ScreenCaptureKit
    # has no shadow/cursor toggles parity issue here (cursor default on).
    if not args.full and not args.all_displays and has_screencapturekit():
        win = resolve_window(args.owner)
        try:
            from _sck import capture_window_still
            capture_window_still(win["window_id"], str(o))
            emit_path(o)
            return 0
        except (ImportError, RuntimeError) as e:
            # fall through to legacy CLI if the SCK path fails at runtime
            print("probe-runner: ScreenCaptureKit capture failed (%s); "
                  "falling back to screencapture CLI" % e, file=sys.stderr)

    if args.full:
        cmd = [cap, "-x", str(o)]
    else:
        win = resolve_window(args.owner)
        cmd = [cap, "-x", "-l", str(win["window_id"])]
        if args.no_shadow:
            cmd.append("-o")
        if args.cursor:
            cmd.append("-C")
        cmd.append(str(o))

    run(cmd)
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
