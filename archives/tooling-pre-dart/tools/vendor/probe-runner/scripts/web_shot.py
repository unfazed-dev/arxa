#!/usr/bin/env python3
"""Screenshot the active web target.

Usage:
  web_shot.py                     # viewport
  web_shot.py --full              # full-page
  web_shot.py --element "<sel>"   # element bounding box
  web_shot.py --out PATH
  web_shot.py --browser=safari    # fallback: macOS screencapture of Safari window
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, out_path
from _web import cdp_send, cdp_session, ensure_browser


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--full", action="store_true")
    p.add_argument("--element")
    p.add_argument("--out")
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    args = p.parse_args()

    try:
        engine, handle = ensure_browser(args.browser)
    except Exception as e:
        die(str(e))

    o = Path(args.out) if args.out else out_path("web", "png")

    if engine == "chrome":
        ws = handle["webSocketDebuggerUrl"]
        params = {"format": "png", "fromSurface": True, "captureBeyondViewport": bool(args.full)}
        if args.element:
            # Persistent session: DOM nodeIds die when the inspector ws closes.
            with cdp_session(ws) as s:
                doc = s.send("DOM.getDocument")
                node = s.send("DOM.querySelector", {
                    "nodeId": doc["root"]["nodeId"], "selector": args.element,
                })
                if not node.get("nodeId"):
                    die(f"element not found: {args.element}")
                box = s.send("DOM.getBoxModel", {"nodeId": node["nodeId"]})
                margin = box["model"]["margin"]
                x = min(margin[0], margin[2], margin[4], margin[6])
                y = min(margin[1], margin[3], margin[5], margin[7])
                w = max(margin[0], margin[2], margin[4], margin[6]) - x
                h = max(margin[1], margin[3], margin[5], margin[7]) - y
                params["clip"] = {"x": x, "y": y, "width": w, "height": h, "scale": 1}
                result = s.send("Page.captureScreenshot", params)
        else:
            result = cdp_send(ws, "Page.captureScreenshot", params)
        o.write_bytes(base64.b64decode(result["data"]))
        emit_path(o)
        return 0

    # safari fallback: WebDriver `get_screenshot_as_png`
    png = handle.get_screenshot_as_png()
    o.write_bytes(png)
    handle.quit()
    emit_path(o)
    return 0


if __name__ == "__main__":
    sys.exit(main())
