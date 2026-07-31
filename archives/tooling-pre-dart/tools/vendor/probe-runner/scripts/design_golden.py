#!/usr/bin/env python3
"""Render a design HTML bundle in Chrome (CDP) and capture a region golden PNG.

The design-side half of the fidelity loop. `color_assert` / `pixdiff` compare
device screenshots, but against WHAT? Against a golden rendered from the design's
own source. This probe renders bundle.html (a runnable React+Babel app) headless
in Chrome at device DPR, drives it to a requested state, and screenshots a
CSS-selector region — producing the ground-truth PNG the built app must match.

WHY THIS EXISTS (the freeze bug). The capture layer reads getComputedStyle() at
ONE instant — one state. A `:disabled` rule (e.g. .primary:disabled bg=bone-3)
read at capture (when the form is empty) freezes the disabled colour as the
button's eternal colour, hiding the enabled colour (accent). This probe drives
the design to MULTIPLE states (disabled vs enabled) and screenshots each, so a
golden exists for every state — closing the loop state-conditional CSS opens.

State-driving: --drive 'selector=value' sets an input's value + dispatches the
React-aware input event, so the component re-renders (e.g. injecting a valid
email flips the Send-code button enabled). --click 'selector' clicks first.
Multiple --drive / --click flags apply in order.

Device DPR: Chrome is set to a CSS viewport matching the target device and the
screenshot captured at `deviceScaleFactor` so 1 CSS px == 1 device px (matches
flutter_shot's coordinate space — color_assert/pixdiff then compose directly).

Emits JSON: {image, rect, viewport, state} and writes the PNG. rc=0 on success.

Usage:
  # disabled-state golden of the Send-code button:
  design_golden.py bundle.html --selector '.auth-btn.primary' --out disabled.png

  # enabled-state golden (inject a valid email first):
  design_golden.py bundle.html --selector '.auth-btn.primary' --out enabled.png \
      --drive 'input[type=email]=test@example.com'

  # full-screen golden (no selector):
  design_golden.py bundle.html --out full.png
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, out_path, emit_json
from _web import ensure_browser, cdp_target, cdp_session, chrome_running, chrome_launch


def _file_url(path: str) -> str:
    abs_ = os.path.abspath(path)
    return "file://" + abs_


def _drive(s, css: str, value: str | None, click: bool) -> None:
    """Drive the React app to a state: set an input value (React-aware) or click.

    Uses the native input setter + dispatchEvent so React's onChange fires (the
    naive .value= doesn't — React overrides the value property). This is the same
    technique react-testing-library uses; it's the canonical way to drive React."""
    if click:
        # click() on the resolved element
        s.send("Runtime.evaluate", {"expression":
            f'(function(){{var e=document.querySelector({css!r});if(e)e.click();}})()'})
        time.sleep(0.15)
        return
    if value is not None:
        # the React-aware value setter: reach the prototype's descriptor, set, dispatch
        setter_js = (
            '(function(){'
            f'var el=document.querySelector({css!r});if(!el)return false;'
            'var proto=el.tagName==="TEXTAREA"?HTMLTextAreaElement.prototype:'
            'HTMLInputElement.prototype;'
            'var desc=Object.getOwnPropertyDescriptor(proto,"value");'
            'if(desc&&desc.set)desc.set.call(el,'
            f'  {json.dumps(value)});else el.value={json.dumps(value)};'
            'el.dispatchEvent(new Event("input",{bubbles:true}));'
            'el.dispatchEvent(new Event("change",{bubbles:true}));'
            'return true;})()'
        )
        res = s.send("Runtime.evaluate", {"expression": setter_js,
                                          "returnByValue": True})
        ok = (res.get("result", {}) or {}).get("value", False)
        if not ok:
            die(f"--drive: no element matched {css!r}")
        time.sleep(0.2)  # let React re-render


def _rect_of(s, css: str) -> tuple[int, int, int, int]:
    """A CSS selector's bounding rect in CSS px via getBoundingClientRect."""
    res = s.send("Runtime.evaluate", {
        "expression": f'(function(){{var e=document.querySelector({css!r});if(!e)return"";'
                      f'var r=e.getBoundingClientRect();return [r.left,r.top,r.width,r.height].map(function(n){{return Math.round(n)}}).join(",");}})()',
        "returnByValue": True})
    val = (res.get("result", {}) or {}).get("value", "")
    if not val:
        die(f"selector {css!r} did not match any element")
    x, y, w, h = (int(float(v)) for v in val.split(","))
    if w <= 0 or h <= 0:
        die(f"selector {css!r} has zero size ({w}x{h}) — not rendered?")
    return x, y, w, h


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("bundle", help="design HTML bundle (React+Babel or static)")
    p.add_argument("--selector", help="CSS selector to crop to (omit = full page)")
    p.add_argument("--out", help="output PNG path")
    p.add_argument("--drive", action="append", default=[],
                   help="drive state: 'cssSelector=value' (React-aware, fires onChange)")
    p.add_argument("--click", action="append", default=[],
                   help="drive state: click a 'cssSelector'")
    p.add_argument("--viewport", default="390x844",
                   help="CSS viewport WxH (iPhone 14/15 logical = 390x844; default)")
    p.add_argument("--dpr", type=float, default=3.0,
                   help="deviceScaleFactor (iPhone = 3; default 3.0)")
    p.add_argument("--settle", type=float, default=1.5,
                   help="seconds to wait after load for React+Babel to render (default 1.5)")
    args = p.parse_args()

    if not os.path.exists(args.bundle):
        die(f"bundle not found: {args.bundle}")

    # launch / attach Chrome
    if not chrome_running():
        try:
            chrome_launch()
        except Exception as e:
            die(f"could not launch Chrome: {e}")
        time.sleep(1.0)
    if not chrome_running():
        die("Chrome not running / not reachable on the CDP port")

    target = cdp_target()
    if not target or "webSocketDebuggerUrl" not in target:
        die("no CDP page target — open Chrome with a tab")
    ws = target["webSocketDebuggerUrl"]

    try:
        vw, vh = (int(v) for v in args.viewport.lower().split("x"))
    except (ValueError, AttributeError):
        die(f"--viewport expects WxH (got {args.viewport!r})")

    with cdp_session(ws) as s:
        # set device metrics so the screenshot's coordinate space matches a device
        s.send("Emulation.setDeviceMetricsOverride", {
            "width": vw, "height": vh, "deviceScaleFactor": args.dpr,
            "mobile": True, "screenWidth": vw, "screenHeight": vh,
        })
        url = _file_url(args.bundle)
        s.send("Page.enable")
        s.send("Page.navigate", {"url": url})
        # wait for load + the React/Babel boot (the bundle compiles JSX in-browser)
        time.sleep(args.settle)
        # drive to the requested state, in flag order
        for d in args.drive:
            if "=" not in d:
                die(f"--drive expects 'selector=value' (got {d!r})")
            css, val = d.split("=", 1)
            _drive(s, css.strip(), val, click=False)
        for c in args.click:
            _drive(s, c.strip(), None, click=True)
        time.sleep(0.4)  # final settle after state change

        # capture
        fmt = "png"
        cap = s.send("Page.captureScreenshot", {"format": fmt, "captureBeyondViewport": False})
        data_b64 = cap.get("data")
        if not data_b64:
            die("captureScreenshot returned no data")
        full_png = base64.b64decode(data_b64)
        out = Path(args.out) if args.out else out_path("design_golden", "png", kind="golden")
        out.write_bytes(full_png)

        # crop to selector if given (report the CSS-px rect for downstream tools)
        rect = None
        if args.selector:
            rect = _rect_of(s, args.selector)

    emit_path(out)
    # also print a small JSON sidecar with the rect (captureBeyondViewport=False →
    # coords are CSS px in the device-pixel screenshot, scaled by dpr)
    if rect:
        x, y, w, h = rect
        emit_json({
            "image": str(out),
            "selector": args.selector,
            "css_rect": {"x": x, "y": y, "w": w, "h": h},
            "device_rect": {"x": int(x * args.dpr), "y": int(y * args.dpr),
                            "w": int(w * args.dpr), "h": int(h * args.dpr)},
            "dpr": args.dpr, "viewport": {"w": vw, "h": vh},
        })
    return 0


if __name__ == "__main__":
    sys.exit(main())
