#!/usr/bin/env python3
"""MANUAL live-smoke harness for the LANDED web-capture stack (P0-P15 CSS
coverage + G3b cross-route token merge + ARIA). NOT a pytest (no test_ prefix ->
not collected): it drives live Chrome (CDP :9222) over localhost-served fixtures
and validates the REAL produced artifact -- real captured field VALUES + a clean
content_firewall.audit_bundle on the produced bundle AND the web_states delta
tree (the non-key-stripped P4/P5 leak site).

WHY a manual script, not a suite test: a hand-authored skeleton is the keys-proxy
that false-passed the G3d gate (memory: validate-real-artifact-not-keys-proxy),
so the validation MUST be a real capture -- but a live capture against a single
shared mutable Chrome tab is too slow (minutes; pathological when the tab is
wedged) and stateful to belong in the unit suite. Run it by hand before releases.

PREREQ: a debug Chrome with EXACTLY ONE page target (memory:
cdp-capture-needs-open-tab). The capture's target-resolution picks a page target;
with >1 tab it can attach to a STALE tab and hang (observed: multi-minute hangs
after a killed run left zombie tabs). Open one fresh tab, close the rest:
  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=9222
Then:  python3 scripts/livesmoke_web_capture.py
Runtime ~3-4 min (two full route captures + a web_states drive) — opt-in, slow by
nature; that slowness is WHY this is a manual script and not a suite test.
Exit 0 = real artifact captured AND firewall-clean. Non-zero = failure (printed).
"""
import functools
import glob
import http.server
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS)
import content_firewall as cf  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(SCRIPTS), "fixtures")
CDP_PORT = 9222


def _free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def _run(cmd, timeout):
    return subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True, timeout=timeout)


def main():
    port = _free_port()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=FIXTURES)
    httpd = http.server.HTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % port
    out = tempfile.mkdtemp(prefix="livesmoke_")
    fails = []
    try:
        routes = [base + "/interaction-state/disclosure.html",
                  base + "/scroll-motion/multi-band.html"]
        rf = os.path.join(out, "routes.txt")
        open(rf, "w").write("\n".join(routes))
        site = os.path.join(out, "site")

        r = _run([sys.executable, "site_capture.py", "--urls-file", rf, "--out", site,
                  "--cdp-port", str(CDP_PORT), "--merge", "--dedup"], 180)
        if r.returncode != 0:
            fails.append("site_capture rc=%d: %s" % (r.returncode, (r.stderr or r.stdout)[-300:]))
        # stdout IS the pretty-printed manifest JSON object -- parse the whole thing.
        manifest = json.loads(r.stdout[r.stdout.index("{"):]) if "{" in r.stdout else {}
        if manifest.get("ok_count") != 2:
            fails.append("ok_count != 2: %s" % manifest)
        if manifest.get("post", {}).get("merge", {}).get("status") != "ok":
            fails.append("merge not ok: %s" % manifest.get("post"))
        if manifest.get("post", {}).get("dedup", {}).get("status") != "ok":
            fails.append("dedup not ok: %s" % manifest.get("post"))

        skels = glob.glob(os.path.join(site, "**", "skeleton.json"), recursive=True)
        if len(skels) != 2:
            fails.append("skeleton.json count=%d (want 2)" % len(skels))
        if skels:
            sk = json.loads(open(skels[0]).read())
            nodes = sk.get("nodes", [])
            if not nodes:
                fails.append("empty skeleton -- no nodes captured")
            if nodes and not all("bbox" in n for n in nodes):
                fails.append("nodes missing real bbox")
            styled = [n for n in nodes if n.get("style")]
            if not styled:
                fails.append("no node carries a real computed-style map")
            elif not isinstance(next(iter(styled[0]["style"].values())), str):
                fails.append("style value is not real captured bytes")
        if not os.path.exists(os.path.join(site, "site.json")):
            fails.append("G3a site.json manifest missing")

        states = os.path.join(out, "states.json")
        rs = _run([sys.executable, "web_states.py", "--url",
                   base + "/interaction-state/multi-trigger.html",
                   "--out", states, "--cdp-port", str(CDP_PORT)], 90)
        if rs.returncode != 0:
            fails.append("web_states rc=%d: %s" % (rs.returncode, (rs.stderr or rs.stdout)[-300:]))
        if os.path.exists(states) and not json.loads(open(states).read()).get("base_nodes"):
            fails.append("states capture has no base nodes")

        vs = cf.audit_bundle(site)
        vst = cf.audit_bundle(out)
        if vs:
            fails.append("FIREWALL: %d violations in produced site bundle: %s" % (len(vs), vs[:3]))
        if vst:
            fails.append("FIREWALL: %d violations in produced states tree: %s" % (len(vst), vst[:3]))
    finally:
        httpd.shutdown()

    if fails:
        print("LIVE-SMOKE FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print("LIVE-SMOKE PASS: real artifact captured (skeleton+tokens+G3b merge+dedup+states), "
          "real field values present, firewall 0 violations on produced bundle AND states tree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
