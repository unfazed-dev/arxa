#!/usr/bin/env python3
"""Close axes 2-3: positively exercise the remaining untested substrate/motion archs via
known references (absent on awwwards). One Chrome, detection-only + one controlled test:
  lottie  -> getAnimations blind to bodymovin rAF motion? (G7-class)
  astro   -> islands present + DOM-captured
  flutter -> CanvasKit = whole-app canvas, ~zero semantic DOM (extreme G5)
  xorigin -> DOMSnapshot cannot pierce a cross-origin iframe (controlled inject)"""
import json, os, sys, time, urllib.request
from types import SimpleNamespace
from pathlib import Path
SCRIPTS = os.environ.get("PROBE_RUNNER_SCRIPTS", str(Path(__file__).resolve().parents[2] / "scripts"))
sys.path.insert(0, SCRIPTS)
OUT = Path(__file__).resolve().parent / "out"; OUT.mkdir(exist_ok=True)
PORT = 9334
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


def stabilize(cap=12):
    prev, st, t0 = -1, 0, time.time()
    while time.time() - t0 < cap:
        n = rt("document.querySelectorAll('*').length") or 0
        if n == prev and n > 10:
            st += 1
            if st >= 2:
                break
        else:
            st = 0
        prev = n; time.sleep(0.5)
    time.sleep(1.0)


out = {}

# --- LOTTIE ---
navigate(ev, engine, "https://lottiefiles.com/"); stabilize()
out["lottie"] = rt(r"""(function(){var ga=0;try{ga=document.getAnimations().length;}catch(e){}
  return {url:location.href, lottie_els:document.querySelectorAll('lottie-player,dotlottie-player,[data-animation-path]').length,
    has_lib:!!(window.lottie||window.bodymovin), getAnimations:ga,
    svg:document.querySelectorAll('svg').length, canvas:document.querySelectorAll('canvas').length,
    nodes:document.querySelectorAll('*').length};})();""")

# --- ASTRO ISLANDS ---
navigate(ev, engine, "https://astro.build/"); stabilize()
out["astro"] = rt(r"""(function(){var ga=0;try{ga=document.getAnimations().length;}catch(e){}
  return {url:location.href, astro_islands:document.querySelectorAll('astro-island').length,
    next:!!window.__NEXT_DATA__, getAnimations:ga, nodes:document.querySelectorAll('*').length,
    scrollH:document.documentElement.scrollHeight};})();""")

# --- FLUTTER / CANVASKIT ---
navigate(ev, engine, "https://gallery.flutter.dev/"); stabilize(16)
out["flutter"] = rt(r"""(function(){var vw=innerWidth*innerHeight;
  var cv=[].slice.call(document.querySelectorAll('canvas'));var carea=0,webgl=0;
  cv.forEach(function(c){var r=c.getBoundingClientRect();carea+=Math.max(0,r.width)*Math.max(0,r.height);
    try{if(c.getContext('webgl2')||c.getContext('webgl'))webgl++;}catch(e){}});
  return {url:location.href, canvas:cv.length, webgl_canvas:webgl, canvas_area_ratio:vw?+(carea/vw).toFixed(2):0,
    flt_glass:document.querySelectorAll('flt-glass-pane,flt-scene-host,flutter-view').length,
    semantic_nodes:document.querySelectorAll('flt-semantics,[role]').length,
    light_nodes:document.querySelectorAll('*').length, scrollH:document.documentElement.scrollHeight};})();""")
# what does web_skeleton's parse see on a CanvasKit app?
snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                    {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True, "includePaintOrder": True})
try:
    out["flutter"]["parse_recs"] = len(ws.parse_snapshot(snap, ws.WANT_STYLES, dpr=(rt("devicePixelRatio") or 2.0)))
except Exception as e:
    out["flutter"]["parse_recs"] = "err:" + str(e)[:50]

# --- CROSS-ORIGIN IFRAME (controlled) ---
navigate(ev, engine, "https://example.com/"); stabilize(8)
rt(r"""(function(){
  var f1=document.createElement('iframe');f1.src='https://www.iana.org/';f1.id='xo';f1.style='width:400px;height:300px';
  document.body.appendChild(f1);
  var f2=document.createElement('iframe');f2.src=location.origin+'/';f2.id='so';f2.style='width:400px;height:300px';
  document.body.appendChild(f2);return true;})();""")
time.sleep(4.0)
snap2 = ev.sess.send("DOMSnapshot.captureSnapshot",
                     {"computedStyles": ws.WANT_STYLES, "includeDOMRects": True, "includePaintOrder": True})
out["xorigin"] = rt(r"""(function(){
  var xo=document.getElementById('xo'),so=document.getElementById('so');
  function acc(f){try{return !!(f && f.contentDocument && f.contentDocument.body);}catch(e){return false;}}
  return {documents_in_snapshot:%d, xorigin_contentDoc_accessible:acc(xo),
    sameorigin_contentDoc_accessible:acc(so)};})();""" % len(snap2.get("documents", [])))

Path(OUT / "ref2.json").write_text(json.dumps(out, default=str, indent=2))
L = out["lottie"]; A = out["astro"]; F = out["flutter"]; X = out["xorigin"]
print("LOTTIE  %s" % L.get("url"))
print("   lottie_els=%s has_lib=%s getAnimations=%s svg=%s canvas=%s | hypothesis G7-class if els>0 & getAnimations~0" % (
    L.get("lottie_els"), L.get("has_lib"), L.get("getAnimations"), L.get("svg"), L.get("canvas")))
print("ASTRO   %s" % A.get("url"))
print("   astro_islands=%s nodes=%s getAnimations=%s  -> islands present + DOM-captured (capture-equiv to SPA/MPA)" % (
    A.get("astro_islands"), A.get("nodes"), A.get("getAnimations")))
print("FLUTTER %s" % F.get("url"))
print("   canvas=%s webgl=%s canvas_area_ratio=%s flt_glass=%s semantic_nodes=%s light_nodes=%s parse_recs=%s" % (
    F.get("canvas"), F.get("webgl_canvas"), F.get("canvas_area_ratio"), F.get("flt_glass"),
    F.get("semantic_nodes"), F.get("light_nodes"), F.get("parse_recs")))
print("XORIGIN inject example.com + cross-origin iana.org iframe + same-origin iframe")
print("   snapshot_documents=%s xorigin_contentDoc=%s sameorigin_contentDoc=%s  -> cross-origin = opaque boundary" % (
    X.get("documents_in_snapshot"), X.get("xorigin_contentDoc_accessible"), X.get("sameorigin_contentDoc_accessible")))
print("wrote /tmp/aw/ref2.json")
ev.close()
