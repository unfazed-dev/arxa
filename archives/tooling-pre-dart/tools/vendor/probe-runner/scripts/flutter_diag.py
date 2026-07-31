#!/usr/bin/env python3
"""Toggle Flutter perf overlay / repaint rainbow / slow animations.

Usage:
  flutter_diag.py perf on|off
  flutter_diag.py repaint on|off
  flutter_diag.py slow <factor>           # 1.0 normal, 5.0 = 5x slower
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import first_isolate, rpc


def main() -> int:
    p = argparse.ArgumentParser(prog="flutter_diag.py", description=__doc__)
    p.add_argument("kind", choices=("perf", "repaint", "slow"))
    p.add_argument("val")
    args = p.parse_args()
    kind, val = args.kind, args.val

    # Flutter registers these as *string* service extensions — params are
    # accepted as stringified values, not native JSON types. Sending a JSON
    # bool causes the extension to never reply (WS recv times out).
    #
    # Some toggles (notably `showPerformanceOverlay` on the macOS desktop
    # embedder) are also known to take effect without acking the RPC: the
    # send arrives, the flag flips, but no response frame is ever written.
    # We wrap each call with a short timeout and degrade to fire-and-forget
    # so a working toggle isn't reported as a failure.
    try:
        iso = first_isolate()
    except RuntimeError as e:
        die(str(e))

    if kind == "perf":
        method, params = "ext.flutter.showPerformanceOverlay", {"enabled": "true" if val == "on" else "false"}
    elif kind == "repaint":
        method, params = "ext.flutter.repaintRainbow", {"enabled": "true" if val == "on" else "false"}
    elif kind == "slow":
        method, params = "ext.flutter.timeDilation", {"timeDilation": str(float(val))}
    else:
        die("unknown kind")
        return 2

    try:
        r = rpc(method, params, isolate=iso, timeout=3.0)
        emit_json({"kind": kind, "val": val, "result": r})
        return 0
    except Exception as e:
        msg = str(e)
        if "timed out" in msg.lower() or "Connection timed out" in msg:
            emit_json({
                "kind": kind, "val": val, "dispatched": True,
                "note": "extension did not ack within 3s — common for "
                        "showPerformanceOverlay on the macOS desktop embedder. "
                        "The flag may still have taken effect; verify visually.",
            })
            return 0
        die(msg)
        return 2


if __name__ == "__main__":
    sys.exit(main())
