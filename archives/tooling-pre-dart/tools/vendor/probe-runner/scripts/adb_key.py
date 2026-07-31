#!/usr/bin/env python3
"""Send a keyevent on Android.

Usage:
  adb_key.py <KEYCODE_NAME|integer>

Common: HOME, BACK, MENU, POWER, VOLUME_UP, VOLUME_DOWN, ENTER, TAB, ESCAPE,
        WAKEUP, SLEEP, DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT.
Names without the KEYCODE_ prefix are accepted (auto-prefixed).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import emit_json


def main() -> int:
    p = argparse.ArgumentParser(description="Send an Android keyevent.")
    p.add_argument("key", help="KEYCODE_* name, bare key name (auto-prefixed), or integer")
    args = p.parse_args()
    key = args.key
    if not key.startswith("KEYCODE_") and not key.isdigit():
        key = "KEYCODE_" + key
    adb_cmd(["shell", "input", "keyevent", key])
    emit_json({"key": key})
    return 0


if __name__ == "__main__":
    sys.exit(main())
