#!/usr/bin/env python3
"""Preflight a TCC permission scope and report status.

Usage:
  tcc_check.py                       # check every supported scope
  tcc_check.py screen_recording      # check one scope, exit 0/3
  tcc_check.py accessibility --json  # JSON output

Supported scopes: screen_recording, accessibility.

Exit codes:
  0  granted (or all granted when no scope passed)
  3  denied for the requested scope
  4  preflight API unavailable on this host
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import TCC_SCOPES, emit_json, tcc_status


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("scope", nargs="?", choices=TCC_SCOPES)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    scopes = [args.scope] if args.scope else list(TCC_SCOPES)
    report = {s: tcc_status(s) for s in scopes}

    if args.json:
        emit_json(report)
    else:
        for s, state in report.items():
            label = "granted" if state is True else ("denied" if state is False else "unknown")
            print(f"{s}: {label}")

    if args.scope:
        state = report[args.scope]
        if state is True:
            return 0
        if state is False:
            return 3
        return 4
    # batch mode: 0 if every scope granted, 3 if any denied, 4 if any unknown
    if any(v is False for v in report.values()):
        return 3
    if any(v is None for v in report.values()):
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
