#!/usr/bin/env python3
"""SAME-PIPELINE isolation (kills the cross-pipeline-ratio caveat). For cartier/air/sowieso,
in ONE cold session per origin, run web_skeleton's OWN captureSnapshot+parse_snapshot at 3
points — all the SAME pipeline, so deltas are pure acquisition, not pipeline mismatch:
  C1 = at verb-timing (~2s after nav, NO dismiss)        == what the verb actually emits
  C2 = hydrated, NO dismiss                              (timing effect = C2 - C1)
  C3 = hydrated, AFTER consent dismiss                   (consent effect = C3 - C2)
If C3 ~ C2 => overlays COVER the DOM, don't remove it => consent does NOT bite capture
(advisor's claim). One Chrome; each origin is cold for consent (per-origin cookies)."""
import json, sys, time, urllib.request
from types import SimpleNamespace
from pathlib import Path
SCRIPTS = "/Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner/scripts"
sys.path.insert(0, SCRIPTS)
OUT = Path(__file__).resolve().parent / "out"; OUT.mkdir(exist_ok=True)
PORT = 9334
SITES = [("cartier", "https://www.cartier.com/en-fr/watchesandwonders"),
         ("air", "https://aircenter.space/"),
         ("sowieso", "https://sowieso.wero-wallet.eu/nl-en/merchant")]
for _ in range(60):
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % PORT, timeout=1).read(); break
    except Exception:
        time.sleep(0.5)
from _web_eval import resolve_web_eval, navigate
import web_skeleton as ws

args = SimpleNamespace(browser="chrome", url="about:blank", android=False, ios=False, cdp_port=PORT, serial=None)
engine, ev, dev = resolve_web_eval(args)
ev.sess.send("DOMSnapshot.enable", {})


def rt(expr):
    try:
        r = ev.sess.send("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": False})
        return None if "exceptionDetails" in r else r.get("result", {}).get("value")
    except Exception:
        return None


def parse_now():
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True, "includePaintOrder": True})
    dpr = (rt("devicePixelRatio") or 2.0)
    try:
        recs = ws.parse_snapshot(snap, ws.WANT_STYLES, dpr=dpr)
        return len(recs)
    except Exception as e:
        return "err:" + str(e)[:60]


OVERLAY = r"""(function(){var k=['onetrust','didomi','cookiebot','cky-','consent','gdpr'];
  var a=[].slice.call(document.querySelectorAll('div,section,aside'));
  for(var i=0;i<a.length;i++){var s=((a[i].id||'')+' '+(a[i].className||'')+'').toLowerCase();
    for(var j=0;j<k.length;j++)if(s.indexOf(k[j])>=0&&a[i].offsetParent!==null)return true;}return false;})();"""
DISMISS = r"""(function(){var sels=['#onetrust-accept-btn-handler','#didomi-notice-agree-button',
  '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll','.cky-btn-accept','button[id*=accept i]'];
  for(var i=0;i<sels.length;i++){try{var e=document.querySelector(sels[i]);if(e&&e.offsetParent!==null){e.click();return sels[i];}}catch(x){}}
  var b=[].slice.call(document.querySelectorAll('button,a[role=button]'));
  for(var j=0;j<b.length;j++){var t=(b[j].textContent||'').trim().toLowerCase();
    if(/^(accept all|accept|agree|i agree|got it|allow all|ok)$/.test(t)&&b[j].offsetParent!==null){b[j].click();return 't:'+t;}}
  return null;})();"""

res = []
for label, url in SITES:
    navigate(ev, engine, url)   # location.assign + ~2s
    c1 = parse_now()                       # verb-timing, no dismiss
    ov1 = bool(rt(OVERLAY)); l1 = rt("document.querySelectorAll('*').length")
    # hydrate-wait WITHOUT dismiss
    prev, st, t0 = -1, 0, time.time()
    while time.time() - t0 < 22:
        n = rt("document.querySelectorAll('*').length") or 0
        if n == prev and n > 10 and rt("document.readyState") == "complete":
            st += 1
            if st >= 3:
                break
        else:
            st = 0
        prev = n; time.sleep(0.5)
    time.sleep(1.0)
    c2 = parse_now()                        # hydrated, no dismiss
    ov2 = bool(rt(OVERLAY)); l2 = rt("document.querySelectorAll('*').length")
    dism = rt(DISMISS); time.sleep(1.3)
    c3 = parse_now()                        # hydrated, dismissed
    l3 = rt("document.querySelectorAll('*').length")
    row = dict(label=label, url=url, c1_verbtiming=c1, c2_hydrated_nodismiss=c2, c3_hydrated_dismissed=c3,
               overlay_at_c1=ov1, overlay_at_c2=ov2, dismissed=dism,
               light_c1=l1, light_c2=l2, light_c3=l3)
    res.append(row)
    def d(a, b):
        return (b - a) if isinstance(a, int) and isinstance(b, int) else "n/a"
    print("[%s] %s" % (label, url))
    print("   C1 verb-timing(~2s,no-dismiss) parse=%s  light=%s overlay=%s" % (c1, l1, ov1))
    print("   C2 hydrated(no-dismiss)        parse=%s  light=%s overlay=%s" % (c2, l2, ov2))
    print("   C3 hydrated(dismissed:%s)      parse=%s  light=%s" % (dism, c3, l3))
    print("   >>> TIMING effect (C2-C1)=%s | CONSENT effect (C3-C2)=%s" % (d(c1, c2), d(c2, c3)))

Path(OUT / "iso.json").write_text(json.dumps(res, default=str, indent=2))
print("wrote /tmp/aw/iso.json")
ev.close()
