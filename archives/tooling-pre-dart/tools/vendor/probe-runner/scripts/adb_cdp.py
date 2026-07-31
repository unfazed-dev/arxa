#!/usr/bin/env python3
"""Forward Android Chrome/WebView CDP socket to localhost and run CDP ops.

Usage:
  adb_cdp.py forward                       # adb forward + print port
  adb_cdp.py targets                       # list pages
  adb_cdp.py eval "document.title"
  adb_cdp.py dom --selector "<css>"
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd
from _common import die, emit_json


def _do_forward(port: int = 9223) -> None:
    adb_cmd(["forward", f"tcp:{port}", "localabstract:chrome_devtools_remote"])


def _targets(port: int) -> list[dict]:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2) as r:
        return json.loads(r.read())


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("verb", choices=["forward", "targets", "eval", "dom"])
    p.add_argument("expr", nargs="?")
    p.add_argument("--selector")
    p.add_argument("--port", type=int, default=9223)
    args = p.parse_args()

    if args.verb == "forward":
        _do_forward(args.port)
        emit_json({"forwarded": args.port})
        return 0

    try:
        targets = _targets(args.port)
    except Exception:
        _do_forward(args.port)
        try:
            targets = _targets(args.port)
        except Exception as e:
            die(f"could not reach Chrome CDP on port {args.port}: {e} "
                f"(launch Chrome on device first via adb_url chrome://newtab "
                f"and enable USB debugging for Chrome in chrome://inspect)")

    if args.verb == "targets":
        emit_json(targets)
        return 0

    pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        die("no Chrome page targets")
    ws = pages[0]["webSocketDebuggerUrl"]

    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        die("missing websocket-client: pip3 install websocket-client")

    conn = create_connection(ws, timeout=10)
    if args.verb == "eval":
        if not args.expr:
            die("expr required")
        conn.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
            "expression": args.expr, "returnByValue": True,
        }}))
    else:  # dom
        if not args.selector:
            die("--selector required")
        conn.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
            "expression": f"document.querySelector({args.selector!r})?.outerHTML",
            "returnByValue": True,
        }}))
    while True:
        msg = json.loads(conn.recv())
        if msg.get("id") == 1:
            emit_json(msg.get("result", msg))
            break
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
