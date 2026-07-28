#!/usr/bin/env python3
"""Dump the page accessibility tree (Chrome only).

Usage:
  web_a11y.py [--root <selector>]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import cdp_send, cdp_session, cdp_target, chrome_running


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--root")
    p.add_argument("--browser", default="chrome", choices=["chrome", "safari"])
    args = p.parse_args()

    if args.browser == "safari":
        die("accessibility tree not available on safari via probe-runner "
            "(use --browser chrome)", code=2)

    if not chrome_running():
        die("Chrome not running with CDP")

    ws = cdp_target()["webSocketDebuggerUrl"]
    if args.root:
        with cdp_session(ws) as s:
            doc = s.send("DOM.getDocument")
            node = s.send("DOM.querySelector", {
                "nodeId": doc["root"]["nodeId"], "selector": args.root,
            })
            if not node.get("nodeId"):
                die(f"selector not found: {args.root}")
            result = s.send("Accessibility.getPartialAXTree", {"nodeId": node["nodeId"]})
    else:
        result = cdp_send(ws, "Accessibility.getFullAXTree")
    emit_json(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
