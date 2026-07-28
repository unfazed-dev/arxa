#!/usr/bin/env python3
"""Type text on Android via `adb shell input text`.

Usage:
  adb_type.py "<text>"
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Type text on Android.")
    p.add_argument("text", help="text to send; spaces are encoded for `input text`")
    args = p.parse_args()
    # `input text` requires spaces to be encoded as %s
    payload = args.text.replace(" ", "%s")
    adb_cmd(["shell", "input", "text", payload])
    emit_json({"typed": len(args.text)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
