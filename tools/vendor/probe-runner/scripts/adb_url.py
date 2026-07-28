#!/usr/bin/env python3
"""Open a URL / deep link on Android.

Usage:
  adb_url.py <url>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Open URL / deep link via android.intent.action.VIEW.")
    p.add_argument("url")
    args = p.parse_args()
    adb_cmd(["shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", args.url])
    emit_json({"opened": args.url})
    return 0


if __name__ == "__main__":
    sys.exit(main())
