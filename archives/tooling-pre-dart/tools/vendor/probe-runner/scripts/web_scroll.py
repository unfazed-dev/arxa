#!/usr/bin/env python3
"""Scroll a selector into view, or scroll the page by px.

Usage:
  web_scroll.py --selector "<css>"
  web_scroll.py --by 0,500
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import cdp_send, ensure_browser


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--selector")
    p.add_argument("--by", help="DX,DY in CSS px")
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    if not args.selector and not args.by:
        die("pass --selector or --by")

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    if args.selector:
        js = f"document.querySelector({args.selector!r})?.scrollIntoView({{behavior:'instant',block:'center'}})"
    else:
        dx, dy = args.by.split(",")
        js = f"window.scrollBy({int(dx)},{int(dy)})"

    if engine == "chrome":
        cdp_send(handle["webSocketDebuggerUrl"], "Runtime.evaluate", {
            "expression": js, "returnByValue": True,
        })
        emit_json({"engine": "chrome", "ok": True})
        return 0

    handle.execute_script(js)
    emit_json({"engine": "safari", "ok": True})
    handle.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
