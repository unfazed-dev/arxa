#!/usr/bin/env python3
"""Grant / revoke / reset privacy permissions.

Usage:
  ios_privacy.py grant|revoke|reset <service> <bundle-id>

services: all, calendar, contacts-limited, contacts, location, location-always,
photos-add, photos, media-library, microphone, motion, reminders, siri
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_privacy.py", description=__doc__)
    p.add_argument("action", choices=("grant", "revoke", "reset"))
    p.add_argument("service")
    p.add_argument("bundle_id", metavar="<bundle-id>")
    args = p.parse_args()
    action, service, bid = args.action, args.service, args.bundle_id
    r = subprocess.run(
        ["xcrun", "simctl", "privacy", "booted", action, service, bid],
        check=False, capture_output=True, text=True,
    )
    if r.returncode != 0:
        die(f"simctl privacy failed: {r.stderr.strip() or r.stdout.strip()}",
            code=r.returncode or 2)
    emit_json({"action": action, "service": service, "bundle": bid})
    return 0


if __name__ == "__main__":
    sys.exit(main())
