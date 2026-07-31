#!/usr/bin/env python3
"""Poll an AX subtree for changes and emit a NDJSON stream.

True AXObserver callbacks require a CFRunLoop. For a polling fallback,
this script dumps the tree at intervals and prints diffs.

Usage:
  ax_observe.py <owner> [--interval 1.0] [--seconds 30]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import resolve_window  # noqa


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("--interval", type=float, default=1.0)
    p.add_argument("--seconds", type=float, default=30.0)
    args = p.parse_args()

    import subprocess

    script = Path(__file__).with_name("ax_tree.py")
    end = time.monotonic() + args.seconds
    prev: str | None = None
    while time.monotonic() < end:
        r = subprocess.run(
            ["python3", str(script), args.owner, "--max-depth", "4"],
            capture_output=True, text=True, check=False,
        )
        cur = r.stdout
        if cur != prev:
            sys.stdout.write(json.dumps({"ts": time.time(), "tree": cur and json.loads(cur)}) + "\n")
            sys.stdout.flush()
            prev = cur
        time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
