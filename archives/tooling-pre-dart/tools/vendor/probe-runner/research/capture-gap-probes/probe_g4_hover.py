#!/usr/bin/env python3
"""G4 hover / non-ARIA trigger DE-RISK probe (bar: docs/plans/g4-hover-trigger-derisk.md).

Question: does extending the G4 (`web_states`) explicit-ARIA trigger scan to (a) hover-revealed
menus and (b) JS-custom no-ARIA click triggers recover materially more CONTENT-FREE revealed
structure than the ARIA-click baseline, on REAL sites, and is the extra trigger set findable on a
content-free basis (CDP getEventListeners listener-types) with enough precision to ship?

Measured on the basis a content-free BUILD ships: the `_states.diff_skeletons` APPEARED unit + the
project shape-key (`probe_g3d_dedup._node_key`). new_shapes = distinct content-free shapes a detector
reveals that REST and the ARIA scan do NOT. Two detectors, measured SEPARATELY:
  L (listener): drive only candidates whose CDP getEventListeners shows a click/hover listener
                (content-free-clean; a plain <a href> has no listener -> excluded -> precision honest).
  H (CSS-hover sweep): CDP Input mouseMoved over the bounded candidate set regardless of listener
                (catches pure-CSS :hover menus L misses; the hard tail).

Mechanism pins (getting these wrong = a G2-style tautology):
  - CSS :hover fires ONLY via CDP Input.dispatchMouseEvent (mouseMoved), NOT a JS dispatchEvent.
  - el.click() (_CLICK_JS) DOES fire JS click listeners -> the no-ARIA click class needs new
    DETECTION, not a new drive.
  - getEventListeners is per-node (event DELEGATION on an ancestor is invisible to L -> Detector-H
    still catches delegated *hover* reveals empirically; click-delegation is an honest L blind spot).

HOST Bash, CDP :9222. De-risk ONLY: does not modify web_states.py / _states.py / the engine.
Fixtures (existence-proof + negative control) are served over a localhost HTTP server.
"""
from __future__ import annotations

import argparse
import http.server
import json
import shutil
import socket
import socketserver
import sys
import tempfile
import threading
import time
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
FIXTURES = ROOT / "fixtures" / "interaction-state"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import content_firewall as cf                       # redact_node, audit_bundle
from probe_g3d_dedup import _node_key               # content-free shape-key (drop=() == full key)
from web_skeleton import _snapshot_skeleton         # the real engine seam web_states uses
from web_states import _AFFORD_JS, _CLICK_JS        # exact ARIA scan + click drive
from _states import classify_trigger, diff_skeletons
from _web_eval import resolve_web_eval, navigate

# ---- pre-registered cohort + thresholds (LOCKED — docs/plans/g4-hover-trigger-derisk.md) ----
SITES = [
    {"id": "R1-bootstrap", "kind": "real",
     "urls": ["https://getbootstrap.com/docs/5.3/components/dropdowns/",
              "https://getbootstrap.com/docs/5.3/components/navbar/"]},
    {"id": "R2-mdn", "kind": "real",
     "urls": ["https://developer.mozilla.org/en-US/",
              "https://www.smashingmagazine.com/"]},
    {"id": "R3-hn", "kind": "real",
     "urls": ["https://news.ycombinator.com/",
              "https://www.gnu.org/licenses/gpl-3.0.html"]},
    {"id": "F1-hovermenu", "kind": "fixture", "fixture": "hover-menu.html"},
    {"id": "N1-staticneg", "kind": "neg", "fixture": "static-neg.html"},
]
NEW_ABS = 25            # new_shapes absolute floor (per detector)
PRECISION_MIN = 0.20    # listener-detector precision floor on real pass-sites
NEG_MAX = 10            # negative control must stay below this (both detectors)
HIT_MIN = 3             # a "hit" = a drive revealing >= this many appeared nodes
MIN_REAL_PASS_SITES = 2 # real (NOT fixture) pass-sites needed
CANDIDATE_CAP = 400     # cursor:pointer candidate cap (bounding pre-filter; log if hit)
VIS_MARGIN = 2          # laid-out-count increase that gates an (expensive) post-snapshot

CLICK_TYPES = {"click", "mousedown", "pointerdown"}
HOVER_TYPES = {"mouseover", "mouseenter", "pointerover", "pointerenter"}

# cursor:pointer candidates with a structural content-free path; ARIA set excluded in Python.
_CAND_JS = r"""
(() => {
  const path = (el) => {
    const parts = [];
    while (el && el.nodeType === 1) {
      const tag = el.tagName.toLowerCase();
      let n = 1, sib = el;
      while ((sib = sib.previousElementSibling)) { if (sib.tagName === el.tagName) n++; }
      parts.unshift(tag + ':nth-of-type(' + n + ')');
      el = el.parentElement;
    }
    return parts.join(' > ');
  };
  const out = [];
  for (const el of document.querySelectorAll('*')) {
    const cs = getComputedStyle(el);
    if (cs.cursor !== 'pointer') continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    out.push(path(el));
  }
  return out;
})()
"""
# laid-out element count: display:none->block reveals INCREASE it (a non-laid-out node has no
# client rect). Cheap change-proxy that gates the expensive DOMSnapshot to actual reveals.
_VIS_JS = ("(() => { let n = 0; for (const e of document.querySelectorAll('*')) "
           "{ if (e.getClientRects().length) n++; } return n; })()")


def _shapes(nodes):
    return {_node_key(n) for n in nodes}


def _firewall_violations(sk):
    """Audit the SHIPPED artifact (redact_node), not raw capture — the G2 firewall fix."""
    d = Path(tempfile.mkdtemp(prefix="g4fw_"))
    try:
        shipped = {"nodes": [cf.redact_node(n) for n in sk["nodes"]]}
        (d / "skeleton.json").write_text(json.dumps(shipped))
        return cf.audit_bundle(d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _snap(ev, url):
    return _snapshot_skeleton(ev, url)[0]


def _center(ev, sel):
    return ev.ev(
        "(() => { const e = document.querySelector(%s); if (!e) return null;"
        " const r = e.getBoundingClientRect();"
        " if (r.width <= 0 || r.height <= 0) return null;"
        " return {x: Math.round(r.left + r.width/2), y: Math.round(r.top + r.height/2)}; })()"
        % json.dumps(sel))


def _hover(ev, x, y):
    ev.sess.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})


def _unhover(ev):
    ev.sess.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": 0, "y": 0})


def _listeners(ev, sel):
    """Content-free listener-type set for an element (CDP DOMDebugger.getEventListeners)."""
    r = ev.sess.send("Runtime.evaluate",
                     {"expression": "document.querySelector(%s)" % json.dumps(sel),
                      "returnByValue": False})
    oid = (r.get("result") or {}).get("objectId")
    if not oid:
        return set()
    try:
        got = ev.sess.send("DOMDebugger.getEventListeners", {"objectId": oid})
    except Exception:
        return set()
    return {l.get("type") for l in (got.get("listeners") or [])}


def _aria_baseline(ev, url, rest_sk):
    """The existing ARIA-click scan: total appeared + the shape set it reveals (exclude REST)."""
    rest_shapes = _shapes(rest_sk["nodes"])
    cands = ev.ev(_AFFORD_JS) or []
    triggers = [c for c in cands if classify_trigger(c)]
    appeared, shapes, viol, driven = 0, set(), 0, 0
    aria_sels = {c["selector"] for c in cands}
    for c in triggers:
        try:
            pre = _snap(ev, url)
            if not ev.ev(_CLICK_JS % json.dumps(c["selector"])):
                continue
            driven += 1
            time.sleep(0.3)
            after = _snap(ev, url)
            viol += len(_firewall_violations(after))
            appeared += diff_skeletons(pre, after)["n_appeared"]
            shapes |= (_shapes(after["nodes"]) - _shapes(pre["nodes"]))
            ev.ev(_CLICK_JS % json.dumps(c["selector"]))  # best-effort toggle back
            time.sleep(0.15)
        except Exception:
            continue
    return {"aria_triggers": driven, "aria_appeared": appeared,
            "aria_shapes": shapes, "aria_sels": aria_sels,
            "rest_shapes": rest_shapes, "aria_fw": viol}


def _drive_candidates(ev, url, rest_sk, base, cap):
    """Run Detector-L (listener-positive) + Detector-H (hover-all) over cursor:pointer candidates."""
    excl = base["rest_shapes"] | base["aria_shapes"]
    rest_vis = ev.ev(_VIS_JS)
    raw = ev.ev(_CAND_JS) or []
    cands = [s for s in raw if s not in base["aria_sels"]]
    capped = len(cands) > cap
    cands = cands[:cap]

    drivenL = hitsL = drivenH = hitsH = fw = 0
    revL, revH = set(), set()

    def revealed_shapes(pre_sk, after_sk):
        return (_shapes(after_sk["nodes"]) - _shapes(pre_sk["nodes"])) - excl

    for sel in cands:
        try:
            c = _center(ev, sel)
            if not c:
                continue
            types = _listeners(ev, sel)
            has_click = bool(types & CLICK_TYPES)
            has_hover = bool(types & HOVER_TYPES)

            # ---- HOVER gesture: Detector-H always; Detector-L if a hover listener ----
            _unhover(ev); time.sleep(0.05)
            _hover(ev, c["x"], c["y"]); time.sleep(0.25)
            hov_hit = False
            if ev.ev(_VIS_JS) > rest_vis + VIS_MARGIN:
                after = _snap(ev, url)
                fw += len(_firewall_violations(after))
                if diff_skeletons(rest_sk, after)["n_appeared"] >= HIT_MIN:
                    hov_hit = True
                    rs = revealed_shapes(rest_sk, after)
                    revH |= rs
                    if has_hover:
                        revL |= rs
            drivenH += 1; hitsH += int(hov_hit)
            if has_hover:
                drivenL += 1; hitsL += int(hov_hit)
            _unhover(ev); time.sleep(0.05)

            # ---- CLICK gesture: Detector-L only, listener-positive ----
            if has_click:
                pre = _snap(ev, url)
                if ev.ev(_CLICK_JS % json.dumps(sel)):
                    time.sleep(0.3)
                    after = _snap(ev, url)
                    fw += len(_firewall_violations(after))
                    drivenL += 1
                    if diff_skeletons(pre, after)["n_appeared"] >= HIT_MIN:
                        hitsL += 1
                        revL |= revealed_shapes(pre, after)
                    ev.ev(_CLICK_JS % json.dumps(sel))  # best-effort toggle back
                    time.sleep(0.15)
        except Exception:
            continue

    return {
        "cand_total": len(raw), "cand_driven": len(cands), "cand_capped": capped,
        "driven_L": drivenL, "hits_L": hitsL,
        "precision_L": round(hitsL / drivenL, 3) if drivenL else 0.0,
        "new_shapes_L": len(revL),
        "driven_H": drivenH, "hits_H": hitsH,
        "precision_H": round(hitsH / drivenH, 3) if drivenH else 0.0,
        "new_shapes_H": len(revH),
        "fw_detect": fw,
    }


def _measure(ev, url):
    rest_sk = _snap(ev, url)
    base = _aria_baseline(ev, url, rest_sk)
    det = _drive_candidates(ev, url, rest_sk, base, CANDIDATE_CAP)
    return {
        "rest_nodes": len(rest_sk["nodes"]),
        "aria_triggers": base["aria_triggers"], "aria_appeared": base["aria_appeared"],
        "aria_shapes": len(base["aria_shapes"]),
        **det,
        "firewall_violations": base["aria_fw"] + det["fw_detect"],
    }


def _run_site(site, port, http_port):
    out = {"id": site["id"], "kind": site["kind"]}
    if site["kind"] in ("fixture", "neg"):
        urls = ["http://127.0.0.1:%d/%s" % (http_port, site["fixture"])]
    else:
        urls = site["urls"]
    for url in urls:
        args = SimpleNamespace(browser="auto", url=url, android=False, ios=False,
                               cdp_port=port, serial=None)
        try:
            engine, ev, _dev = resolve_web_eval(args)
        except SystemExit as e:
            out["load"] = "transport-fail: %s" % e
            continue
        try:
            navigate(ev, engine, url)
            res = _measure(ev, url)
            res["url"] = url
            return {"id": site["id"], "kind": site["kind"], "load": "ok", **res}
        except Exception as e:  # noqa: BLE001 - log + try next fallback url
            out["load"] = "error: %s: %s" % (type(e).__name__, e)
        finally:
            try:
                ev.close()
            except Exception:
                pass
    return out


def _verdict(rows):
    real_pass, neg_fail, fw_fail, hard_tail = [], [], [], []
    for r in rows:
        if r.get("load") != "ok" or "new_shapes_L" not in r:
            continue
        if r.get("firewall_violations", 0) > 0:
            fw_fail.append(r["id"])
        if r["kind"] == "real":
            if r["new_shapes_L"] >= NEW_ABS and r["precision_L"] >= PRECISION_MIN:
                real_pass.append(r["id"])
            elif r["new_shapes_H"] >= NEW_ABS and r["new_shapes_L"] < NEW_ABS:
                hard_tail.append(r["id"])  # reveals only via CSS-hover sweep
        elif r["kind"] == "neg":
            if r["new_shapes_L"] >= NEG_MAX or r["new_shapes_H"] >= NEG_MAX:
                neg_fail.append(r["id"])
    ok = (len(real_pass) >= MIN_REAL_PASS_SITES and not neg_fail and not fw_fail)
    return {
        "real_pass_sites": real_pass, "hard_tail_only": hard_tail,
        "neg_control_fail": neg_fail, "firewall_fail": fw_fail,
        "MIN_REAL_PASS_SITES": MIN_REAL_PASS_SITES,
        "verdict": "BUILD-JUSTIFIED" if ok else "DEFER",
    }


def _serve(port):
    h = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=str(FIXTURES), **k)
    httpd = socketserver.TCPServer(("127.0.0.1", port), h)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def _free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close()
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    a = ap.parse_args()
    http_port = _free_port()
    httpd = _serve(http_port)
    try:
        rows = [_run_site(s, a.cdp_port, http_port) for s in SITES]
    finally:
        httpd.server_close()
    verdict = _verdict(rows)
    print(json.dumps({"rows": rows, "verdict": verdict,
                      "bar": {"NEW_ABS": NEW_ABS, "PRECISION_MIN": PRECISION_MIN,
                              "NEG_MAX": NEG_MAX, "HIT_MIN": HIT_MIN,
                              "MIN_REAL_PASS_SITES": MIN_REAL_PASS_SITES,
                              "CANDIDATE_CAP": CANDIDATE_CAP}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
