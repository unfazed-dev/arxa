#!/usr/bin/env python3
"""Send a hardware key event to the iOS sim.

Usage:
  ios_key.py <keycode>                              # raw HID code via `idb ui key`
  ios_key.py home|lock|side|sidebutton|siri|applepay
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_run
from _common import die, emit_json

# `idb ui button` choices (live, idb 1.1+): APPLE_PAY, HOME, LOCK, SIDE_BUTTON, SIRI.
# Volume up/down and "power" are NOT exposed by idb ui button. The iPhone side
# button is the lock button; we alias both 'lock' and 'power' to LOCK.
HW_MAP = {
    "home": "HOME",
    "lock": "LOCK",
    "power": "LOCK",
    "side": "SIDE_BUTTON",
    "sidebutton": "SIDE_BUTTON",
    "siri": "SIRI",
    "applepay": "APPLE_PAY",
    "apple_pay": "APPLE_PAY",
}

UNSUPPORTED_BUTTONS = {"volup", "voldown", "volumeup", "volumedown"}


def main() -> int:
    p = argparse.ArgumentParser(
        prog="ios_key.py",
        description=__doc__,
        usage="ios_key.py <keycode|home|lock|side|siri|applepay>",
    )
    p.add_argument("key", metavar="<keycode|name>")
    args = p.parse_args()
    arg = args.key.lower()
    if arg in UNSUPPORTED_BUTTONS:
        die(
            f"'{arg}' is not exposed by `idb ui button` (choices: "
            f"APPLE_PAY, HOME, LOCK, SIDE_BUTTON, SIRI). "
            f"For volume control, dispatch a raw HID keycode via `idb ui key` "
            f"(volume up=0x80, volume down=0x81 in some sim builds — verify "
            f"against your iOS version).",
            code=2,
        )
    if arg in HW_MAP:
        r = subprocess.run(
            ["idb", "ui", "button", HW_MAP[arg]],
            check=False, capture_output=True, text=True,
        )
        if r.returncode != 0:
            die(f"idb ui button failed: {r.stderr.strip() or r.stdout.strip()}",
                code=r.returncode or 2)
        emit_json({"key": arg, "button": HW_MAP[arg]})
        return 0
    # Anything else: treat as a raw HID keycode integer for `idb ui key`.
    idb_run(["ui", "key", args.key], capture=True)
    emit_json({"key": args.key})
    return 0


if __name__ == "__main__":
    sys.exit(main())
