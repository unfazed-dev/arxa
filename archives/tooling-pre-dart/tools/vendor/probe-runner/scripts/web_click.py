#!/usr/bin/env python3
"""Click a DOM element by CSS selector in the active web target.

Usage:
  web_click.py "<selector>"
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
    p.add_argument("selector")
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    if engine == "chrome":
        ws = handle["webSocketDebuggerUrl"]
        cdp_send(ws, "Runtime.evaluate", {
            "expression": f"document.querySelector({args.selector!r})?.click()",
            "returnByValue": True,
        })
        emit_json({"clicked": args.selector})
        return 0

    from selenium.webdriver.common.by import By  # type: ignore
    handle.find_element(By.CSS_SELECTOR, args.selector).click()
    emit_json({"engine": "safari", "clicked": args.selector})
    handle.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
