#!/usr/bin/env python3
"""Set the active Chrome page's device emulation (viewport + DPR + UA).

Chrome only.

Usage:
  web_emu.py --device iPhone-12             # known presets
  web_emu.py --size 390x844 --dpr 3 --mobile
  web_emu.py --reset
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _web import cdp_send, cdp_target, chrome_running


PRESETS = {
    "iPhone-12": {"width": 390, "height": 844, "deviceScaleFactor": 3, "mobile": True,
                  "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"},
    "iPhone-SE": {"width": 375, "height": 667, "deviceScaleFactor": 2, "mobile": True,
                  "userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"},
    "iPad": {"width": 820, "height": 1180, "deviceScaleFactor": 2, "mobile": True,
             "userAgent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"},
    "Pixel-7": {"width": 412, "height": 915, "deviceScaleFactor": 2.625, "mobile": True,
                "userAgent": "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36"},
}


def _device_arg(s: str) -> str:
    """Accept both 'iPhone 12' and 'iPhone-12' forms; normalize to dashed."""
    key = s.replace(" ", "-")
    if key not in PRESETS:
        raise argparse.ArgumentTypeError(
            f"invalid device '{s}' (choose from {sorted(PRESETS)})"
        )
    return key


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--device", type=_device_arg,
                   help=f"device preset; one of {sorted(PRESETS)} "
                        f"(spaces and dashes both accepted)")
    p.add_argument("--size", help="WxH")
    p.add_argument("--dpr", type=float, default=2.0)
    p.add_argument("--mobile", action="store_true")
    p.add_argument("--ua")
    p.add_argument("--reset", action="store_true")
    p.add_argument("--browser", default="chrome", choices=["chrome", "safari"])
    args = p.parse_args()

    if args.browser == "safari":
        die("device emulation not available on safari "
            "(Chrome DevTools Protocol only — use --browser chrome)", code=2)

    if not chrome_running():
        die("Chrome not running with CDP")

    ws = cdp_target()["webSocketDebuggerUrl"]

    if args.reset:
        cdp_send(ws, "Emulation.clearDeviceMetricsOverride")
        cdp_send(ws, "Network.setUserAgentOverride", {"userAgent": ""})
        emit_json({"reset": True})
        return 0

    if args.device:
        params = dict(PRESETS[args.device])
    else:
        if not args.size:
            die("pass --device or --size WxH")
        w, h = args.size.lower().split("x")
        params = {
            "width": int(w), "height": int(h),
            "deviceScaleFactor": args.dpr, "mobile": bool(args.mobile),
        }
        if args.ua:
            params["userAgent"] = args.ua

    ua = params.pop("userAgent", None)
    cdp_send(ws, "Emulation.setDeviceMetricsOverride", params)
    if ua:
        cdp_send(ws, "Network.setUserAgentOverride", {"userAgent": ua})
    emit_json({"applied": {**params, "userAgent": ua}})
    return 0


if __name__ == "__main__":
    sys.exit(main())
