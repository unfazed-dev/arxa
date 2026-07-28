#!/usr/bin/env python3
"""DE-RISK harness (NOT a pytest; manual, headless real-site). Pseudo-element GEOMETRY follow-on.

§C9-R-P8 captures ::before/::after/::marker STYLE but DROPS their bbox (_collect_pseudo keeps only
sparse style). `parse_snapshot` already reads bounds[i] for every layout row incl. pseudo rows, so
geometry is captured-then-discarded. Question (real-artifact, NOT a fixture proxy): do REAL decorative
pseudos carry non-degenerate bounds that are NOT trivially derivable from the originator's bbox?

For each pseudo layout row: compare its OWN bounds vs its ORIGINATOR's bounds (parentIndex). Classify
degenerate (w<=0|h<=0) / parent-equal (~same box) / DISTINCT (own size or offset). Bar in
docs/plans/pseudo-element-geometry-derisk.md.

Run: python3 scripts/derisk_pseudo_geometry.py   (Chrome + websocket-client)
"""
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _web import chrome_binary, CDPSession  # noqa: E402
from web_skeleton import WANT_STYLES          # noqa: E402

PAGES = [
    "https://getbootstrap.com/docs/5.3/getting-started/introduction/",
    "https://en.wikipedia.org/wiki/Cascading_Style_Sheets",
    "https://tailwindcss.com/",
]
EPS = 1.0  # px tolerance for "same box"


def _launch(udd, url):
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
         "--window-size=1440,900", f"--user-data-dir={udd}", url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pf = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if pf.exists():
            t = pf.read_text().splitlines()
            if t:
                return p, int(t[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-port"); sys.exit(2)


def _ws(port):
    for _ in range(60):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2) as r:
                tg = [t for t in json.loads(r.read()) if t.get("type") == "page"]
            if tg and tg[0].get("webSocketDebuggerUrl"):
                return tg[0]["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(0.2)
    return None


def _approx_equal(a, b):
    return all(abs(a[k] - b[k]) <= EPS for k in range(4))


def analyze(snap):
    strings = snap["strings"]
    content_idx = WANT_STYLES.index("content")
    agg = {"pseudo_rows": 0, "no_layout": 0, "degenerate": 0,
           "parent_equal": 0, "distinct": 0, "distinct_styled": 0, "styled": 0}
    samples = []
    for doc in snap["documents"]:
        nodes = doc["nodes"]
        layout = doc["layout"]
        li = layout["nodeIndex"]
        bounds = layout["bounds"]
        styles = layout["styles"]
        names = nodes["nodeName"]
        parent = nodes.get("parentIndex") or []
        pt = nodes.get("pseudoType") or {}
        pseudo_by_node = {idx: strings[val] if val is not None and val >= 0 else None
                          for idx, val in zip(pt.get("index", []), pt.get("value", []))}
        # dom_index -> layout row (last wins; pseudo & real have distinct dom indices)
        dom2row = {dom: i for i, dom in enumerate(li)}
        for i, dom_i in enumerate(li):
            ps = pseudo_by_node.get(dom_i)
            if ps not in ("before", "after", "marker"):
                continue
            agg["pseudo_rows"] += 1
            srow = styles[i] if i < len(styles) else []
            cval = strings[srow[content_idx]] if content_idx < len(srow) and srow[content_idx] >= 0 else None
            styled = bool(cval and cval.strip().lower() not in ("none", "normal", ""))
            if styled:
                agg["styled"] += 1
            x, y, w, h = bounds[i]
            if w <= 0 or h <= 0:
                agg["degenerate"] += 1
                continue
            # originator bounds
            par = parent[dom_i] if dom_i < len(parent) else -1
            prow = dom2row.get(par)
            pbox = bounds[prow] if prow is not None else None
            if pbox is not None and _approx_equal([x, y, w, h], pbox):
                agg["parent_equal"] += 1
            else:
                agg["distinct"] += 1
                if styled:
                    agg["distinct_styled"] += 1
                if len(samples) < 6:
                    samples.append({
                        "pseudo": "::" + ps,
                        "tag": (strings[names[par]] if par >= 0 and par < len(names) else "?"),
                        "box": [round(x, 1), round(y, 1), round(w, 1), round(h, 1)],
                        "parent_box": [round(v, 1) for v in pbox] if pbox else None,
                        "content_shape": ("empty-str" if cval == '""' else
                                          "url/icon" if cval and "url(" in cval else
                                          "text" if styled else "no-content"),
                    })
    return agg, samples


def main():
    bin_ = chrome_binary()
    print("chrome:", bin_, "\n")
    overall = []
    for url in PAGES:
        with tempfile.TemporaryDirectory() as udd:
            proc, port = _launch(udd, url)
            try:
                ws = _ws(port)
                if not ws:
                    print(url, "-> FATAL no-target\n"); continue
                sess = CDPSession(ws, timeout=20.0)
                try:
                    time.sleep(4.0)  # real-site load settle
                    snap = sess.send("DOMSnapshot.captureSnapshot",
                                     {"computedStyles": WANT_STYLES, "includePaintOrder": True})
                finally:
                    sess.close()
                agg, samples = analyze(snap)
                overall.append((url, agg))
                styled = agg["styled"] or 1
                print(f"=== {url}")
                print(f"  pseudo_rows={agg['pseudo_rows']} styled(content)={agg['styled']} "
                      f"no_layout={agg['no_layout']} degenerate={agg['degenerate']} "
                      f"parent_equal={agg['parent_equal']} distinct={agg['distinct']} "
                      f"distinct&styled={agg['distinct_styled']}")
                pct = 100.0 * agg["distinct_styled"] / styled
                print(f"  -> distinct&styled / styled = {pct:.0f}%  (bar: >=30% on >=2 sites)")
                for s in samples:
                    print("     ", json.dumps(s))
                print()
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except Exception:
                    proc.kill()
    # verdict aid
    clears = 0
    for url, agg in overall:
        styled = agg["styled"] or 1
        if 100.0 * agg["distinct_styled"] / styled >= 30 and agg["distinct"] > 0:
            clears += 1
    print(f"SITES CLEARING bar (>=30% distinct&styled, alignment via distinct>0): {clears}/{len(overall)}")
    print("ALIGNMENT: distinct>0 anywhere proves bounds[i] is the pseudo's OWN box (!= parent).")


if __name__ == "__main__":
    main()
