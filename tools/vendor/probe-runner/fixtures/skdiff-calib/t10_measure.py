#!/usr/bin/env python3
"""T10 (#56) signal probe — which backing-scale signal survives the --viewports
override on a HEADED retina display?

Under Emulation.setDeviceMetricsOverride{deviceScaleFactor:1} the JS
devicePixelRatio is known to read 1 while DOMSnapshot bounds stay at the real
backing scale (2). This dumps THREE candidate signals together so the fix can
pick the one that actually tracks DOMSnapshot:
  A) js_dpr                          = window.devicePixelRatio
  B) layout_metrics_ratio            = getLayoutMetrics.layoutViewport.clientWidth
                                        / cssLayoutViewport.clientWidth
  C) element_bound_ratio (SAME node) = HTML snapshot-bound width
                                        / documentElement.getBoundingClientRect().width

The signal whose value == 2 (matches the 2560-device-px artifact we divide by)
is the correct one. js_dpr is expected to read 1 (the bug). Run direct-Python
against headed Chrome :9222 (NOT ctx sandbox — can't reach the host port).
"""
import json, sys, time
sys.path.insert(0, "/Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts")
import web_skeleton as ws
from _web_eval import _remote_cdp_eval, navigate

URL = "http://127.0.0.1:8137/fixture.html"
ev, _ = _remote_cdp_eval(9222, URL)
navigate(ev, "chrome", URL)


def html_device_width(snap):
    """Device-px bound width of the <html> (documentElement) node from the snapshot
    — the SAME element measured in CSS via getBoundingClientRect below."""
    doc = snap["documents"][0]
    nodes, layout, strings = doc["nodes"], doc["layout"], snap["strings"]
    names = nodes["nodeName"]
    html_dom = next((i for i, ni in enumerate(names)
                     if ni >= 0 and strings[ni].upper() == "HTML"), None)
    for k, dom_i in enumerate(layout["nodeIndex"]):
        if dom_i == html_dom:
            return layout["bounds"][k][2]
    return None


def probe(force_dsf1):
    if force_dsf1:
        ev.sess.send("Emulation.setDeviceMetricsOverride",
                     {"width": 1280, "height": 1600, "deviceScaleFactor": 1, "mobile": False})
    else:
        ev.sess.send("Emulation.clearDeviceMetricsOverride", {})
    time.sleep(0.3)
    ev.ev(ws._REST_JS)
    time.sleep(0.2)

    js_dpr = ev.ev("devicePixelRatio")
    html_css_w = ev.ev("document.documentElement.getBoundingClientRect().width")
    inner_w = ev.ev("innerWidth")

    lm = ev.sess.send("Page.getLayoutMetrics", {})
    lv = lm.get("layoutViewport", {})
    clv = lm.get("cssLayoutViewport", {})
    lv_w = lv.get("clientWidth")
    clv_w = clv.get("clientWidth")

    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True,
                         "includePaintOrder": True})
    raw_maxw = max(r[2] for r in snap["documents"][0]["layout"]["bounds"])
    html_dev_w = html_device_width(snap)

    def ratio(a, b):
        return round(a / b, 4) if a and b else None

    return {
        "force_dsf1": force_dsf1,
        "A_js_dpr": js_dpr,
        "B_layout_metrics_ratio": ratio(lv_w, clv_w),
        "B_layoutViewport_clientWidth_device": lv_w,
        "B_cssLayoutViewport_clientWidth_css": clv_w,
        "C_element_bound_ratio_SAME_node": ratio(html_dev_w, html_css_w),
        "C_html_device_w": html_dev_w,
        "C_html_css_w": round(html_css_w, 3) if html_css_w else None,
        "innerWidth_css": inner_w,
        "raw_maxW_device": raw_maxw,
    }


out = {"override_dsf1": probe(True), "live_no_override": probe(False)}
with open("/tmp/skdiff-calib/out/t10_signals.json", "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
