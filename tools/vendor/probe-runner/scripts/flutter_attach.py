#!/usr/bin/env python3
"""Discover the Dart VM service URL for a running Flutter app.

Usage:
  flutter_attach.py --url ws://...                    # explicit, just cache it
  flutter_attach.py --tail <log-file>                 # parse a log file for the URL
  flutter_attach.py --auto [--source ios|adb|stdin|host] [--timeout 15]

`--source host` is an alias for `stdin`: pipe `flutter run`'s stdout into
this script when targeting macOS Flutter desktop or Chrome web (no
idb/adb log stream exists for those targets). Alternatively, redirect
`flutter run` output to a log file and pass `--tail <log-file>`.

Note: `flutter run` prints VM service URLs with an auth-code suffix
ending in `=/`. Naive regexes strip the trailing `=`, causing a 403 on
the WebSocket handshake. This script's parser preserves the suffix.
For the simplest workflow, launch with
`flutter run --disable-service-auth-codes` to drop the auth code entirely.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import parse_url_from_text, save_url


def _read_lines(cmd: list[str], timeout: float):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    deadline = time.monotonic() + timeout
    try:
        while proc.stdout and time.monotonic() < deadline:
            line = proc.stdout.readline()
            if not line:
                break
            yield line
    finally:
        proc.terminate()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--url")
    p.add_argument("--tail")
    p.add_argument("--auto", action="store_true")
    p.add_argument("--source", choices=["ios", "adb", "stdin", "host"], default="stdin")
    p.add_argument("--target", choices=["ios", "adb"],
                   help="which device this URL is for (saves to a per-device cache "
                        "so a probe with --target adb resolves it instantly instead "
                        "of re-discovering). Defaults to --source when that's a device.")
    p.add_argument("--timeout", type=float, default=15.0)
    args = p.parse_args()

    # The device this URL belongs to: explicit --target, else --source if it's a device.
    target = args.target or (args.source if args.source in ("ios", "adb") else None)

    if args.url:
        save_url(args.url, target)
        emit_json({"url": args.url})
        return 0

    if args.tail:
        text = Path(args.tail).read_text(errors="replace")
        url = parse_url_from_text(text)
        if not url:
            die("no VM service URL found in log")
        save_url(url, target)
        emit_json({"url": url})
        return 0

    if not args.auto:
        die("pass --url, --tail, or --auto")

    if args.source == "ios":
        cmd = ["idb", "log"]
    elif args.source == "adb":
        cmd = ["adb", "logcat", "-T", "1"]
    else:
        # stdin / host — both consume sys.stdin. `host` is the named alias
        # for macOS/web Flutter targets where there's no idb/adb log stream.
        for line in sys.stdin:
            u = parse_url_from_text(line)
            if u:
                save_url(u, target)
                emit_json({"url": u})
                return 0
        die("EOF without VM service URL")
        return 124

    for line in _read_lines(cmd, args.timeout):
        u = parse_url_from_text(line)
        if u:
            save_url(u, target)
            emit_json({"url": u})
            return 0
    die(f"timeout: no VM service URL on {args.source} within {args.timeout}s")
    return 124


if __name__ == "__main__":
    sys.exit(main())
