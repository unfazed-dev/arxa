#!/usr/bin/env python3
"""Capture a DOM snapshot.

Usage:
  web_dom.py                          # whole-document DOMSnapshot
  web_dom.py --selector "<css>"       # outerHTML of first match
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
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    if engine == "chrome":
        ws = handle["webSocketDebuggerUrl"]
        if args.selector:
            r = cdp_send(ws, "Runtime.evaluate", {
                "expression": f"document.querySelector({args.selector!r})?.outerHTML",
                "returnByValue": True,
            })
            emit_json(r.get("result", r))
        else:
            r = cdp_send(ws, "DOMSnapshot.captureSnapshot", {"computedStyles": []})
            emit_json({"documents": len(r.get("documents", [])), "strings": len(r.get("strings", []))})
        return 0

    if args.selector:
        from selenium.webdriver.common.by import By  # type: ignore
        el = handle.find_element(By.CSS_SELECTOR, args.selector)
        emit_json({"outerHTML": el.get_attribute("outerHTML")})
    else:
        emit_json({"pageSource_chars": len(handle.page_source)})
    handle.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
