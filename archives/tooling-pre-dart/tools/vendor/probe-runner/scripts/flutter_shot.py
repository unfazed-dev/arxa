#!/usr/bin/env python3
"""Render a Flutter screenshot via the VM service (`_flutter.screenshot`).

The VM-service path captures the Flutter scene only (no platform chrome /
status bar). If the app is built in profile/release mode, or rasterisation
is otherwise unavailable, `_flutter.screenshot` returns empty.

Pass `--allow-device-fallback` to opt into a full-device capture
(`xcrun simctl io booted screenshot` for iOS, `adb exec-out screencap -p`
for Android) when the VM path fails. The fallback artifact includes
platform chrome — the emitted JSON tags `"source"` so callers can branch.

Usage:
  flutter_shot.py [--out PATH] [--allow-device-fallback]
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, out_path
from _flutter import first_isolate, rpc


def _vm_capture(dest: Path) -> bool:
    try:
        iso = first_isolate()
        r = rpc("_flutter.screenshot", isolate=iso)
    except Exception:
        return False
    b64 = (r or {}).get("screenshot") or ""
    if not b64:
        return False
    dest.write_bytes(base64.b64decode(b64))
    return True


def _vm_platform() -> str:
    """Return the Dart VM's operatingSystem field, or "" on any error."""
    try:
        vm = rpc("getVM")
    except Exception:
        return ""
    return (vm or {}).get("operatingSystem", "") or ""


def _simctl_capture(dest: Path) -> bool:
    try:
        r = subprocess.run(
            ["xcrun", "simctl", "io", "booted", "screenshot", str(dest)],
            check=False, capture_output=True, text=True,
        )
    except FileNotFoundError:
        return False
    return r.returncode == 0 and dest.exists() and dest.stat().st_size > 0


def _adb_capture(dest: Path) -> bool:
    try:
        with open(dest, "wb") as f:
            r = subprocess.run(
                ["adb", "exec-out", "screencap", "-p"],
                stdout=f, stderr=subprocess.PIPE, check=False,
            )
    except FileNotFoundError:
        return False
    return r.returncode == 0 and dest.stat().st_size > 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out")
    p.add_argument(
        "--allow-device-fallback", action="store_true",
        help="if VM-service screenshot fails, capture the whole device "
             "(simctl on iOS, adb on Android). Output includes platform chrome.",
    )
    args = p.parse_args()

    o = Path(args.out) if args.out else out_path("flutter", "png")

    if _vm_capture(o):
        emit_json({"source": "vm-service", "path": str(o)})
        return 0

    plat = _vm_platform().lower()  # "ios", "android", "macos", "linux", "windows", or ""
    is_mobile = plat in ("ios", "android")

    if not args.allow_device_fallback:
        if is_mobile:
            hint = ("Rerun with --allow-device-fallback to capture the full "
                    "device (simctl / adb) instead. Note: that artifact "
                    "includes platform chrome, not just the Flutter scene.")
        elif plat == "macos":
            hint = ("On macOS Flutter targets, use shot.py <app-owner> "
                    "(Quartz window capture) instead — device fallback "
                    "(simctl / adb) doesn't apply.")
        elif plat in ("linux", "windows"):
            hint = (f"On {plat} Flutter targets, use the host-window capture "
                    "(shot.py <owner> on macOS host equivalents) — device "
                    "fallback (simctl / adb) doesn't apply.")
        else:
            # web target (Dart VM running in browser) or unknown
            hint = ("If the Flutter target is web, use web_shot.py --full to "
                    "capture the Chrome page. Device fallback (simctl / adb) "
                    "doesn't apply outside iOS/Android.")
        die("flutter VM-service screenshot empty — only available on debug "
            "builds. " + hint)

    if is_mobile or not plat:
        if _simctl_capture(o):
            emit_json({"source": "simctl", "path": str(o),
                       "note": "full device frame, not Flutter-scene-only"})
            return 0
        if _adb_capture(o):
            emit_json({"source": "adb", "path": str(o),
                       "note": "full device frame, not Flutter-scene-only"})
            return 0

    die(f"flutter_shot: VM-service returned empty and no fallback applies "
        f"for platform '{plat or 'unknown'}'. "
        f"For macOS: shot.py <owner>. For web: web_shot.py --full. "
        f"For ios/android: ensure a sim/emu is booted.")
    return 2


if __name__ == "__main__":
    sys.exit(main())
