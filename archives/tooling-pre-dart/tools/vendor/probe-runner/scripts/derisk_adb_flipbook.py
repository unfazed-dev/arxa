#!/usr/bin/env python3
"""derisk_adb_flipbook — LIVE validation harness for adb_flipbook.py.

NOT collected by pytest (derisk_* convention). adb_flipbook's pure logic
(parse_bounds, find_view, displacement) is unit-tested in test_adb_flipbook.py;
this script validates the REAL entry point end-to-end against a live emulator:
it drives adb_flipbook.main() with the caller's argv, captures its emitted JSON,
and asserts the displacement oracle agrees with the recovered amplitude.

RECIPE (needs a booted emulator with the target app in the foreground):
  1. adb_boot.py boot <avd>          (or any already-running emulator)
  2. launch the app under test
  3. python3 derisk_adb_flipbook.py --text "<visible view>" \
        --tap-text "<tappable trigger>" --seconds 2.5

The tx_match_px / ty_match_px crosscheck (adb_flipbook emits it as
bounds_crosscheck) should be small for a clean run; this script asserts < 20px.
Mirrors derisk_flutter_skeleton.py: drive the real entry, assert on its output.
"""
from __future__ import annotations

import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
import adb_flipbook as af


def main() -> int:
    if len(sys.argv) == 1 or "--help" in sys.argv:
        print(__doc__)
        return 0

    # Drive the REAL entry point with the caller's argv. adb_flipbook.main()
    # parses argv itself and emit_json()s to stdout; capture that, parse it,
    # and assert on its bounds crosscheck. This validates the production path
    # (argv parsing, device I/O sequencing, output schema, exit codes) — a
    # re-implementation of the pipeline would only validate a stale fork.
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            rc = af.main()
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else 1

    if rc != 0:
        die(f"adb_flipbook.main() exited {rc}")

    try:
        result = json.loads(buf.getvalue())
    except json.JSONDecodeError:
        die("adb_flipbook emitted non-JSON output:\n" + buf.getvalue()[:500])

    cross = result.get("bounds_crosscheck")
    ok = True
    if cross:
        for axis in ("tx_match_px", "ty_match_px"):
            drift = cross.get(axis)
            if drift is not None and abs(drift) >= 20:
                ok = False
    else:
        # no oracle (--auto run): cannot crosscheck, but main() still ran clean
        ok = True

    emit_json({"derisk": "adb_flipbook", "validated": result,
               "crosscheck_ok": ok,
               "ok": bool(result.get("recovery") and ok)})
    return 0 if result.get("recovery") and ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
