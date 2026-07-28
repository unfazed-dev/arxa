#!/usr/bin/env python3
"""Real-retina skeleton_diff CSS-px floor calibration (non-headless Chrome, dpr=2).

Confirmed: on a real retina display DOMSnapshot bounds are DEVICE px, so the
production ÷dpr normalization is correct. This measures:
  - normalization correctness: hero (1200 CSS wide) must read 1200 after ÷dpr in
    BOTH the dpr=2 (retina live) and dpr=1 (deviceScaleFactor:1, --viewports) paths.
  - noise floor: dpr=2 captured twice (same path).
  - cross-dpr floor: dpr=2 vs dpr=1 normalized skeletons -> the real CSS-px floor
    that sets the gate.
"""
import json, sys, time
sys.path.insert(0, "/Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts")
import web_skeleton as ws
import skeleton_diff as sd
from _web_eval import _remote_cdp_eval, navigate

URL = "http://127.0.0.1:8137/fixture.html"
ev, _ = _remote_cdp_eval(9222, URL)
navigate(ev, "chrome", URL)


def capture(force_dsf1):
    """force_dsf1=True mirrors the production --viewports path (deviceScaleFactor:1,
    parse dpr=1). False = retina live path (real dpr=2, parse with real dpr)."""
    if force_dsf1:
        ev.sess.send("Emulation.setDeviceMetricsOverride",
                     {"width": 1280, "height": 1600, "deviceScaleFactor": 1, "mobile": False})
        time.sleep(0.25)
    else:
        ev.sess.send("Emulation.clearDeviceMetricsOverride", {})
        time.sleep(0.25)
    ev.ev(ws._REST_JS)
    time.sleep(0.2)
    layout = ev.ev("({w: innerWidth, h: innerHeight, dpr: devicePixelRatio})")
    page = ev.ev("({w: document.documentElement.scrollWidth, h: document.documentElement.scrollHeight})")
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True, "includePaintOrder": True})
    raw = snap["documents"][0]["layout"]["bounds"]
    raw_maxw = max(r[2] for r in raw)
    eff_dpr = 1.0 if force_dsf1 else (layout["dpr"] or 1.0)
    recs = ws.parse_snapshot(snap, ws.WANT_STYLES, dpr=eff_dpr)
    svg_set, parent_index = set(), None
    for doc in snap["documents"]:
        svg_set |= ws.svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, *_ = ws.to_skeleton(recs, svg_set, parent_index=parent_index, url=URL,
                           viewport={"w": layout["w"], "h": layout["h"], "dpr": layout["dpr"]},
                           page={"w": page["w"], "h": page["h"]})
    hero_w = max((n["bbox"]["w"] for n in sk["nodes"]), default=0)  # widest box ~ hero/footer 1200
    return sk, eff_dpr, raw_maxw, round(hero_w, 3)


LOOSE = {"iou": 0.0, "pos": 1e9, "size": 1e9, "matched_frac": 0.0, "zrank": 0.0, "tree": 0.0}


def measure(a, b):
    r = sd.diff(a, b, LOOSE)
    m = r["measured"]
    pos = sorted((d["pos_err"] for d in r["per_node"]), reverse=True)
    sz = sorted((max(d["w_err"], d["h_err"]) for d in r["per_node"]), reverse=True)
    return {"matched": r["matched"], "of": len(a["nodes"]),
            "max_pos_err": round(m["max_pos_err"], 4),
            "p95_pos_err": round(pos[max(0, len(pos)//20)] if pos else 0, 4),
            "max_size_err": round(m["max_size_err"], 4),
            "min_iou": round(m["min_iou"], 5), "zrank": round(m["zrank"], 4), "tree": round(m["tree"], 4),
            "top_pos": [round(p, 3) for p in pos[:5]]}


sk2a, d2a, rawa, herowa = capture(False)
sk2b, d2b, rawb, herowb = capture(False)
sk1, d1, raw1, herow1 = capture(True)

out = {
    "normalization_check": {
        "dpr2_eff_dpr": d2a, "dpr2_raw_maxW_device": rawa, "dpr2_normalized_maxW_css": herowa,
        "dpr1_eff_dpr": d1, "dpr1_raw_maxW_device": raw1, "dpr1_normalized_maxW_css": herow1,
        "expected_css_maxW": 1200,
        "PASS_dpr2": abs(herowa - 1200) < 1.0, "PASS_dpr1": abs(herow1 - 1200) < 1.0},
    "noise_floor_dpr2_vs_dpr2": measure(sk2a, sk2b),
    "cross_dpr_floor_dpr2_vs_dpr1": measure(sk2a, sk1),
}
with open("/tmp/skdiff-calib/out/calib2.json", "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
