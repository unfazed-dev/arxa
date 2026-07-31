#!/usr/bin/env python3
"""Send a push notification payload to the booted sim.

Usage:
  ios_push.py <bundle-id> <payload-json-path>
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_push.py", description=__doc__)
    p.add_argument("bundle_id", metavar="<bundle-id>")
    p.add_argument("payload", metavar="<payload-json-path>")
    args = p.parse_args()
    bid, payload = args.bundle_id, args.payload
    if not Path(payload).exists():
        die(f"payload not found: {payload}")
    r = subprocess.run(
        ["xcrun", "simctl", "push", "booted", bid, payload],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl push failed: {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"sent": bid, "payload": payload})
    return 0


if __name__ == "__main__":
    sys.exit(main())
