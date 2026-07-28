#!/usr/bin/env python3
"""Navigate the active web target to a URL.

Usage:
  web_open.py <url>                 # Chrome default; Safari fallback
  web_open.py <url> --browser=safari
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
    p.add_argument("url")
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    if engine == "chrome":
        result = cdp_send(handle["webSocketDebuggerUrl"], "Page.navigate", {"url": args.url})
        emit_json({"engine": "chrome", "navigated": args.url, "result": result})
    else:
        handle.get(args.url)
        emit_json({"engine": "safari", "navigated": args.url})
        handle.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
