#!/usr/bin/env python3
"""Type text into a selector in the active web target.

Usage:
  web_type.py "<selector>" "<text>"
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import cdp_send, ensure_browser


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("selector")
    p.add_argument("text")
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    if engine == "chrome":
        ws = handle["webSocketDebuggerUrl"]
        js = (
            f"(()=>{{const el=document.querySelector({args.selector!r});"
            f"if(!el)return false;el.focus();el.value={json.dumps(args.text)};"
            "el.dispatchEvent(new Event('input',{bubbles:true}));return true;})()"
        )
        result = cdp_send(ws, "Runtime.evaluate", {"expression": js, "returnByValue": True})
        emit_json({"engine": "chrome", "typed": args.text, "ok": result.get("result", {}).get("value")})
        return 0

    from selenium.webdriver.common.by import By  # type: ignore
    el = handle.find_element(By.CSS_SELECTOR, args.selector)
    el.clear(); el.send_keys(args.text)
    emit_json({"engine": "safari", "typed": args.text})
    handle.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
