#!/usr/bin/env python3
"""Record network events for the active Chrome page for N seconds.

Chrome only. Safari fallback prints an "unsupported" note.

Usage:
  web_net.py --seconds N [--filter SUBSTR]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import chrome_running, cdp_target


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int, required=True)
    p.add_argument("--filter", dest="filter_")
    p.add_argument("--browser", default="chrome", choices=["chrome", "safari"])
    args = p.parse_args()

    if args.browser == "safari":
        die("network intercept not available on safari (use --browser chrome)", code=2)

    if not chrome_running():
        die("Chrome not running with CDP. run: python3 web_launch.py")

    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        die("missing websocket-client: pip3 install websocket-client")

    target = cdp_target()
    ws = create_connection(target["webSocketDebuggerUrl"], timeout=10)
    ws.send(json.dumps({"id": 1, "method": "Network.enable"}))

    end = time.monotonic() + args.seconds
    events: list[dict] = []
    while time.monotonic() < end:
        try:
            ws.settimeout(0.5)
            msg = json.loads(ws.recv())
        except Exception:
            continue
        if not msg.get("method", "").startswith("Network."):
            continue
        if args.filter_ and args.filter_ not in json.dumps(msg):
            continue
        events.append({"method": msg["method"], "params": msg["params"]})
    ws.close()
    emit_json({"count": len(events), "events": events[-100:]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
