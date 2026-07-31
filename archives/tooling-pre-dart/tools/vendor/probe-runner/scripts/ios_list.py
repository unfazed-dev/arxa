#!/usr/bin/env python3
"""List iOS simulators via `xcrun simctl`."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json, which_or_die


def main() -> int:
    argparse.ArgumentParser(description="List iOS simulators via `xcrun simctl`.").parse_args()
    which_or_die("xcrun", "install Xcode CLI tools: xcode-select --install")
    r = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"],
                       check=False, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"simctl list failed: {r.stderr.strip()}", code=r.returncode or 2)
    emit_json(json.loads(r.stdout))
    return 0


if __name__ == "__main__":
    sys.exit(main())
