#!/usr/bin/env python3
"""MANUAL live-smoke for the G2 --sweep engine. NOT pytest (slow/shared-Chrome).
Validates the LOCKED ship bar's live legs on real artifact bytes:
  cond 1 (realized gain): below_fold.new_shapes >= 25 on the Metafizzy demo and a
          YouTube /watch URL (NOT the consent-flaky home).
  cond 5 (neg control):   below_fold.new_shapes < 0.10*rest_shapes on a static page.
  cond 2 (content-free):  content_firewall.audit_bundle == 0 on each produced bundle.
PREREQ: a debug Chrome with EXACTLY ONE :9222 page target (memory: cdp-capture-needs-open-tab).
  /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222
Usage: python3 scripts/livesmoke_g2.py   (exit 0 = bar's live legs pass)."""
import json
import os
import subprocess
import sys
import tempfile

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS)
import content_firewall as cf  # noqa: E402
import _shape_key as _sk  # noqa: E402

CDP = ["--cdp-port", "9222"]
PASS_SITES = ["https://infinite-scroll.com/demo/full-page/",
              "https://www.youtube.com/watch?v=aqz-KE-bpKQ"]  # /watch: non-consent-gated
NEG_SITE = "https://en.wikipedia.org/wiki/Cat"


def _capture(url, out, sweep):
    sk = os.path.join(out, "sk.json")
    tok = os.path.join(out, "tok.json")
    bundle = os.path.join(out, "bundle")
    cmd = [sys.executable, "web_skeleton.py", "--url", url, "--out", sk] + CDP
    if sweep:
        cmd += ["--sweep", "--sweep-steps", "8"]
    subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True, timeout=240)
    subprocess.run([sys.executable, "web_tokens.py", "--url", url, "--out", tok] + CDP,
                   cwd=SCRIPTS, capture_output=True, text=True, timeout=120)
    subprocess.run([sys.executable, "bundle_writer.py", "--skeleton", sk, "--tokens", tok,
                    "--out", bundle], cwd=SCRIPTS, capture_output=True, text=True, timeout=120)
    return bundle


def _new_shapes(bundle):
    skel = json.loads(open(os.path.join(bundle, "skeleton.json")).read())
    bf = skel.get("below_fold") or {}
    # denominator = distinct REST shape-keys (NOT distinct roles) — matches the locked bar
    # and the probe's len(rest_shapes). Distinct-roles undercounts ~10x -> spurious cond5 fail.
    rest_shapes = len({_sk._node_key(n) for n in skel.get("nodes", [])}) or 1
    return bf.get("new_shapes", 0), rest_shapes


def main():
    fails = []
    for url in PASS_SITES:
        out = tempfile.mkdtemp(prefix="g2_")
        bundle = _capture(url, out, sweep=True)
        new, rest = _new_shapes(bundle)
        viol = len(cf.audit_bundle(bundle) or [])
        print("PASS-SITE %s: new_shapes=%d rest_shapes=%d frac=%.3f firewall=%d"
              % (url, new, rest, new / max(1, rest), viol))
        if new < 25:
            fails.append("cond1 %s: new_shapes=%d (<25)" % (url, new))
        if viol:
            fails.append("cond2 %s: firewall violations" % url)
    out = tempfile.mkdtemp(prefix="g2neg_")
    bundle = _capture(NEG_SITE, out, sweep=True)
    new, rest_shapes = _new_shapes(bundle)
    viol = len(cf.audit_bundle(bundle) or [])
    print("NEG-SITE %s: new_shapes=%d rest_shapes=%d frac=%.3f firewall=%d"
          % (NEG_SITE, new, rest_shapes, new / max(1, rest_shapes), viol))
    if new >= 0.10 * rest_shapes:
        fails.append("cond5 neg: new_shapes=%d >= 0.10*%d" % (new, rest_shapes))
    if viol:
        fails.append("cond2 neg: firewall violations")
    if fails:
        print("G2 LIVE-SMOKE FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print("G2 LIVE-SMOKE PASS: realized gain >=25 on 2 pass-sites, neg control <10%%, firewall 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
