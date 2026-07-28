#!/usr/bin/env python3
"""Tail Chrome page console for N seconds (Chrome only).

Usage:
  web_console.py --seconds N
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die
from _web import cdp_target


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int, required=True)
    p.add_argument("--browser", default="chrome", choices=["chrome", "safari"])
    args = p.parse_args()

    if args.browser == "safari":
        die("console tail not available on safari via probe-runner "
            "(use --browser chrome)", code=2)

    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        die("missing websocket-client: pip3 install websocket-client")

    target = cdp_target()
    ws = create_connection(target["webSocketDebuggerUrl"], timeout=10)
    ws.send(json.dumps({"id": 1, "method": "Runtime.enable"}))
    ws.send(json.dumps({"id": 2, "method": "Log.enable"}))

    end = time.monotonic() + args.seconds
    while time.monotonic() < end:
        try:
            ws.settimeout(0.5)
            msg = json.loads(ws.recv())
        except Exception:
            continue
        if msg.get("method") == "Runtime.consoleAPICalled":
            params = msg["params"]
            sys.stdout.write(json.dumps({
                "ts": params.get("timestamp"),
                "level": params.get("type"),
                "args": [a.get("value") or a.get("description") for a in params.get("args", [])],
            }) + "\n")
            sys.stdout.flush()
        elif msg.get("method") == "Log.entryAdded":
            entry = msg["params"]["entry"]
            sys.stdout.write(json.dumps({
                "ts": entry.get("timestamp"),
                "level": entry.get("level"),
                "msg": entry.get("text"),
            }) + "\n")
            sys.stdout.flush()
    ws.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
