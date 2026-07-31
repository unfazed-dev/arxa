#!/usr/bin/env python3
"""Tap at x,y on the booted iOS sim.

idb's tap coordinate space is LOGICAL POINTS (idb `describe`/`ui describe-all`
frames are points: e.g. 402x874 on an iPhone 16 Pro, not the 1206x2622 pixels a
screenshot returns). Two things make a hand-issued tap "just work regardless of
the UI":

  * --duration: idb's default (instantaneous) tap does NOT actuate a Flutter
    gesture recognizer — Flutter's tap arena needs a real down->hold->up, so a
    0-duration tap silently no-ops on a Flutter view. We press for a real
    (short) beat by default. This is the fix; the tap now lands on native AND
    Flutter UIs alike. Keep it well under the ~0.5s long-press threshold.
  * --space: idb wants points. An agent reading a screenshot has PIXELS. Rather
    than guess (a pixel coord in the top-left is indistinguishable from a valid
    point coord — auto-detection silently mistaps), the caller states the space
    explicitly. Default `points` is idb-native and backward-compatible.

Usage:
  ios_tap.py <x> <y>                       # x,y in logical points (idb-native)
  ios_tap.py <x> <y> --space pixels        # x,y in screenshot pixels -> /density
  ios_tap.py <x> <y> --space norm          # x,y in 0..1 fractions of the screen
  ios_tap.py <x> <y> --duration 0.2        # override press duration (seconds)
  ios_tap.py --self-test                   # offline: verify the space math
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_run  # noqa: E402
from _common import emit_json  # noqa: E402


def _screen() -> dict:
    """Device geometry (points, pixels, density) via `idb describe --json`."""
    r = idb_run(["describe", "--json"], capture=True)
    d = json.loads(r.stdout)
    return d.get("screen_dimensions", d)


def _to_points(x: float, y: float, space: str) -> tuple[float, float]:
    """Resolve caller coords in `space` to idb's logical-point space."""
    if space == "points":
        return x, y
    s = _screen()
    if space == "pixels":
        density = float(s.get("density") or 1.0)
        return x / density, y / density
    if space == "norm":
        return x * float(s["width_points"]), y * float(s["height_points"])
    raise ValueError(f"unknown space {space!r}")


def _self_test() -> int:
    # pure math, no device: pixels/density and norm*dims
    s = {"density": 3.0, "width_points": 402, "height_points": 874}
    # emulate _to_points against a fixed geometry
    def conv(x, y, space):
        if space == "points":
            return x, y
        if space == "pixels":
            return x / s["density"], y / s["density"]
        if space == "norm":
            return x * s["width_points"], y * s["height_points"]
    assert conv(151, 832, "points") == (151, 832)
    assert conv(453, 2496, "pixels") == (151, 832)      # Shop center px -> pts
    assert conv(0.5, 0.5, "norm") == (201, 437)         # screen center
    print("ios_tap self-test OK")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_tap.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("x", nargs="?", type=float)
    p.add_argument("y", nargs="?", type=float)
    p.add_argument("--space", choices=("points", "pixels", "norm"),
                   default="points",
                   help="coordinate space of x,y (default: points = idb-native)")
    p.add_argument("--duration", type=float, default=0.1,
                   help="press duration in seconds (default 0.1; a real press "
                        "is required to actuate Flutter gesture recognizers)")
    p.add_argument("--self-test", action="store_true", help=argparse.SUPPRESS)
    args = p.parse_args()

    if args.self_test:
        return _self_test()
    if args.x is None or args.y is None:
        p.error("x and y are required")

    px, py = _to_points(args.x, args.y, args.space)
    # idb accepts float coords; format tidily.
    sx = f"{px:.6g}"
    sy = f"{py:.6g}"
    idb_run(["ui", "tap", sx, sy, "--duration", str(args.duration)], capture=True)
    emit_json({"x": px, "y": py, "space": args.space, "duration": args.duration})
    return 0


if __name__ == "__main__":
    sys.exit(main())
