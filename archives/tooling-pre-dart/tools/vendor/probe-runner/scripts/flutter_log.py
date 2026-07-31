#!/usr/bin/env python3
"""Stream Dart stdout + Logging events from the VM service.

Usage:
  flutter_log.py [--seconds N]
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die
from _flutter import cached_url, to_ws


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=int, default=0)
    args = p.parse_args()

    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        die("pip3 install websocket-client")

    url = cached_url()
    if not url:
        die("no VM service URL. flutter_attach.py first")
    ws = create_connection(to_ws(url), timeout=10)
    for i, stream in enumerate(["Stdout", "Stderr", "Logging"]):
        ws.send(json.dumps({"jsonrpc": "2.0", "id": i + 1, "method": "streamListen",
                            "params": {"streamId": stream}}))

    deadline = time.monotonic() + args.seconds if args.seconds else None
    try:
        while True:
            if deadline and time.monotonic() > deadline:
                break
            ws.settimeout(0.5)
            try:
                msg = json.loads(ws.recv())
            except Exception:
                continue
            if msg.get("method") == "streamNotify":
                ev = msg["params"]["event"]
                sys.stdout.write(json.dumps({"kind": ev.get("kind"), "data": ev}) + "\n")
                sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    ws.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
