#!/usr/bin/env python3
"""Cheap arch-scanner: detection-only, ONE Chrome, loop URLs. Short-stabilize per site
(NOT fixed-2s — don't rebuild G1 in the scanner). Discovers which untested archs appear
on awwwards: shadow-DOM/web-components, Lottie, Astro-islands, cross-origin iframe,
Three/Rive/WebGPU. Prints one line/site + /tmp/aw/scan.json. No content persisted."""
import json, os, sys, time, urllib.request
from types import SimpleNamespace
from pathlib import Path
SCRIPTS = os.environ.get("PROBE_RUNNER_SCRIPTS", str(Path(__file__).resolve().parents[2] / "scripts"))
sys.path.insert(0, SCRIPTS)
PORT = 9334
URLS = [
    ("unseen",   "https://2025.unseen.co/"),
    ("lookback", "https://tlb.betteroff.studio/"),
    ("corentin", "https://corentinbernadou.com/"),
    ("shed",     "https://shed.design/"),
    ("gqlab",    "https://www.gq.com/sponsored/story/the-extraordinary-lab"),
    ("offmenu",  "http://offmenu.design"),
    ("donmol",   "https://www.donmolinico.es/"),
    ("wildweek", "https://week.wild.plus/athens-26"),
]
for _ in range(60):
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % PORT, timeout=1).read(); break
    except Exception:
        time.sleep(0.5)
from _web_eval import resolve_web_eval, navigate
args = SimpleNamespace(browser="chrome", url="about:blank", android=False, ios=False, cdp_port=PORT, serial=None)
engine, ev, dev = resolve_web_eval(args)


def rt(expr):
    try:
        r = ev.sess.send("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": False})
        return None if "exceptionDetails" in r else r.get("result", {}).get("value")
    except Exception:
        return None


DETECT = r"""(function(){
  function ng(){try{return !!document.querySelector('[ng-version]');}catch(e){return false;}}
  var shadowHosts=[].slice.call(document.querySelectorAll('*')).filter(function(e){return !!e.shadowRoot;});
  var shadowKinds={}; shadowHosts.forEach(function(h){shadowKinds[h.tagName.toLowerCase()]=1;});
  var customEls=[].slice.call(document.querySelectorAll('*')).filter(function(e){return e.tagName.indexOf('-')>0;}).length;
  var cv=[].slice.call(document.querySelectorAll('canvas'));
  var webgl=cv.filter(function(c){try{return !!(c.getContext('webgl2')||c.getContext('webgl'));}catch(e){return false;}}).length;
  var ifr=[].slice.call(document.querySelectorAll('iframe'));
  var xifr=ifr.filter(function(f){try{var o=new URL(f.src,location.href).origin;var r=f.getBoundingClientRect();
     return o!==location.origin && r.width>10 && r.height>10;}catch(e){return false;}}).length;
  return {
    light_nodes: document.querySelectorAll('*').length,
    next:!!window.__NEXT_DATA__, nuxt:!!window.__NUXT__, remix:!!window.__remixContext,
    sveltekit:!!(window.__sveltekit_dev||document.querySelector('[data-sveltekit-hydrate],[data-sveltekit-fetched]')),
    gatsby:!!document.querySelector('#___gatsby'), astro_island:document.querySelectorAll('astro-island').length,
    angular:ng(), vue:!!window.__VUE__, framer:!!(window.__framer__||document.querySelector('[data-framer-name]')),
    client_router: history.pushState.toString().indexOf('[native code]')<0,
    shadow_hosts: shadowHosts.length, shadow_kinds: Object.keys(shadowKinds).slice(0,8),
    custom_elements: customEls,
    canvas: cv.length, webgl: webgl,
    lottie: !!(window.lottie||window.bodymovin)||document.querySelectorAll('lottie-player,dotlottie-player,[data-animation-path]').length>0,
    lottie_els: document.querySelectorAll('lottie-player,dotlottie-player,[data-animation-path]').length,
    three: !!window.THREE, rive: !!(window.rive||window.Rive),
    webgpu: !!navigator.gpu,
    xorigin_iframe: xifr, iframe_total: ifr.length,
    gsap: !!window.gsap, scrolltrigger: (function(){try{return window.ScrollTrigger?window.ScrollTrigger.getAll().length:0;}catch(e){return 0;}})()
  };})();"""

rows = []
for label, url in URLS:
    try:
        navigate(ev, engine, url)
    except Exception:
        pass
    # short stabilize: node-count stable 2x or 8s cap
    prev, stable, t0 = -1, 0, time.time()
    while time.time() - t0 < 8:
        n = rt("document.querySelectorAll('*').length") or 0
        if n == prev and n > 10:
            stable += 1
            if stable >= 2:
                break
        else:
            stable = 0
        prev = n
        time.sleep(0.5)
    time.sleep(0.8)
    d = rt(DETECT) or {"error": True}
    d["label"] = label; d["url"] = url; d["final_url"] = rt("location.href")
    rows.append(d)
    # arch one-liner
    fw = [k for k in ["next", "nuxt", "remix", "sveltekit", "gatsby", "angular", "vue", "framer"] if d.get(k)]
    if d.get("astro_island"):
        fw.append("astro-islands(%s)" % d["astro_island"])
    print("[%-9s] %s" % (label, (d.get("final_url") or url)[:60]))
    print("   fw=%s router=%s | shadow_hosts=%s kinds=%s custom_el=%s | canvas=%s webgl=%s | lottie=%s(%s) three=%s rive=%s webgpu=%s | xorigin_iframe=%s/%s | gsap=%s ST=%s | nodes=%s" % (
        fw or ["none(MPA/static)"], d.get("client_router"), d.get("shadow_hosts"), d.get("shadow_kinds"),
        d.get("custom_elements"), d.get("canvas"), d.get("webgl"), d.get("lottie"), d.get("lottie_els"),
        d.get("three"), d.get("rive"), d.get("webgpu"), d.get("xorigin_iframe"), d.get("iframe_total"),
        d.get("gsap"), d.get("scrolltrigger"), d.get("light_nodes")))

Path(__file__).resolve().parent / "out" / "scan.json".write_text(json.dumps(rows, default=str, indent=2))
# novelty summary
print("\n=== NOVEL ARCH MATCHES ===")
print("shadow-DOM (hosts>0):", [r["label"] for r in rows if (r.get("shadow_hosts") or 0) > 0])
print("astro-islands:", [r["label"] for r in rows if (r.get("astro_island") or 0) > 0])
print("lottie:", [r["label"] for r in rows if r.get("lottie")])
print("cross-origin iframe:", [r["label"] for r in rows if (r.get("xorigin_iframe") or 0) > 0])
print("webgpu:", [r["label"] for r in rows if r.get("webgpu")])
print("three/rive:", [(r["label"], "three" if r.get("three") else "rive") for r in rows if r.get("three") or r.get("rive")])
print("custom-elements>3 (web-comp):", [(r["label"], r.get("custom_elements")) for r in rows if (r.get("custom_elements") or 0) > 3])
ev.close()
