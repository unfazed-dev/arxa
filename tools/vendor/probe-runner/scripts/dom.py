#!/usr/bin/env python3
"""Read a DOM probe out of a Dioxus wry app via the bundled probe template.

This only works if the target crate has `dioxus_debug_probe.rs` installed
and was launched with `--features debug-probe`. The probe writes JSON
responses to stderr lines beginning with `[probe-runner-dom]`.

This script does NOT inject JS itself — it tails the app's stderr (via
`tail_log.py`) and matches the most recent probe payload for the
requested selector.

Usage:
  dom.py <owner> --selector ".brainiac-canvas svg"
  dom.py <owner> --selector "..." --snapshot --max-depth 4
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, iter_lines_until, resolve_window  # noqa


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--selector", required=True)
    p.add_argument("--snapshot", action="store_true")
    p.add_argument("--max-depth", type=int, default=2)
    p.add_argument("--timeout", type=float, default=5.0)
    args = p.parse_args()

    win = resolve_window(args.owner)
    pid = win["pid"]

    cmd = [
        "log", "stream",
        "--style", "compact",
        "--predicate", f'processIdentifier == {pid}',
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    pat = re.compile(r'\[probe-runner-dom\]\s*(\{.*\})')

    print(
        f'waiting up to {args.timeout}s for probe to emit for selector '
        f'"{args.selector}". the app must call '
        f'debug_probe::probe_dom("{args.selector}") (or dom_snapshot) for output.',
        file=sys.stderr,
    )

    deadline = time.monotonic() + args.timeout
    try:
        for line in iter_lines_until(proc, deadline=deadline):
            m = pat.search(line)
            if not m:
                continue
            payload = json.loads(m.group(1))
            if payload.get("selector") == args.selector:
                print(json.dumps(payload, indent=2))
                proc.terminate()
                return 0
    finally:
        proc.terminate()

    die("probe output not seen; is the app instrumented and called the probe?", code=124)
    return 124


if __name__ == "__main__":
    sys.exit(main())
