#!/usr/bin/env python3
"""T10 (#56) LIVE GATE — run the REAL production --viewports path and prove the
fix end-to-end on the headed-retina rig. Not a mock: calls ws._capture_one with
width set (the exact code path the bug lived in). PASS = widest bbox comes back
CSS px (~1280), NOT device px (~2560). Also shows what the OLD ÷1 path emitted."""
import json, os, sys
sys.path.insert(0, os.environ.get("PROBE_RUNNER_SCRIPTS", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts")))
import web_skeleton as ws
from _web_eval import _remote_cdp_eval

URL = "http://127.0.0.1:8137/fixture.html"
ev, _ = _remote_cdp_eval(9222, URL)

# production code path: --viewports sets width -> Emulation dsf:1 -> _backing_scale
sk, layout, page = ws._capture_one(ev, "chrome", URL, width=1280)
maxw = max(n["bbox"]["w"] for n in sk["nodes"])
bs = ws._backing_scale(ev)  # measured under the still-active override

sk_dpr = sk["viewport"]["dpr"]  # must record the TRUE backing scale, not js dpr
out = {
    "viewport_w_css": layout["w"],
    "js_dpr_reported": layout["dpr"],            # the bug: reads 1 under override
    "backing_scale_measured_via_getLayoutMetrics": bs,
    "skeleton_viewport_dpr_recorded": sk_dpr,    # fix: == bs, NOT js dpr (1)
    "max_bbox_w_FIXED_css": round(maxw, 2),
    "max_bbox_w_OLD_div1_would_be_device": round(maxw * bs, 2),
    "PASS_fixed_is_css": 1200 <= maxw <= 1300,
    "PASS_viewport_dpr_is_true_scale": sk_dpr == bs and sk_dpr != layout["dpr"],
    "PROVES_old_bug_doubled": (maxw * bs) > 2000,
}
ev.sess.send("Emulation.clearDeviceMetricsOverride", {})
with open("/tmp/skdiff-calib/out/t10_gate.json", "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
