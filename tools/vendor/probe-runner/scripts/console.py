#!/usr/bin/env python3
"""Tail webview `console.*` output proxied by the Dioxus probe template.

The template installs a JS shim that copies console.log/warn/error calls
into a ring buffer and emits them to host stderr as
`[probe-runner-console] {level, msg, ts}` lines.

Usage:
  console.py <owner> [--seconds N] [--level info|warn|error]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import iter_lines_until, resolve_window  # noqa


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--seconds", type=int, default=0)
    p.add_argument("--level")
    args = p.parse_args()

    win = resolve_window(args.owner)
    cmd = [
        "log", "stream",
        "--style", "compact",
        "--predicate", f'processIdentifier == {win["pid"]}',
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    pat = re.compile(r'\[probe-runner-console\]\s*(.*)')
    deadline = time.monotonic() + args.seconds if args.seconds else None

    try:
        for line in iter_lines_until(proc, deadline=deadline):
            m = pat.search(line)
            if not m:
                continue
            payload = m.group(1)
            if args.level and f'"level":"{args.level}"' not in payload:
                continue
            sys.stdout.write(payload + "\n")
            sys.stdout.flush()
    except KeyboardInterrupt:
        proc.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
