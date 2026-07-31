#!/usr/bin/env python3
"""awwwards reproduction-gap probe. ONE site per invocation. Assumes Chrome already
running on --port (bash wrapper launches/kills per site for isolation).

Measures TRUTH (properly hydrated, gates dismissed) vs VERB-AS-IS (real probe-runner
CLIs, fresh-nav fixed-delay) and writes a compact reproduction-gap scorecard JSON.
No site content persists — only counts/ratios/class-labels (IP firewall).

Advisor constraints folded in:
  #1 detect+dismiss consent/preloader gates, record had_overlay/dismissed/loader_waited
  #2 attribute every low capture to a specific gap label
  #3 canvas-area-% is the substrate-blindness score (canvas motion is unmeasurable)
  #4 skeleton-only verb canary by default; full pipeline only where signal exists
usage: aw_probe.py URL LABEL PORT
"""
import json, os, sys, time, subprocess, urllib.request
from types import SimpleNamespace
from pathlib import Path

SCRIPTS = os.environ.get("PROBE_RUNNER_SCRIPTS", str(Path(__file__).resolve().parents[2] / "scripts"))
sys.path.insert(0, SCRIPTS)
OUTDIR = Path(__file__).resolve().parent / "out"; OUTDIR.mkdir(exist_ok=True)

URL, LABEL, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])

# wait for CDP endpoint
for _ in range(60):
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % PORT, timeout=1).read(); break
    except Exception:
        time.sleep(0.5)

from _web_eval import resolve_web_eval, navigate

args = SimpleNamespace(browser="chrome", url=URL, android=False, ios=False, cdp_port=PORT, serial=None)
engine, ev, dev = resolve_web_eval(args)


def rt(expr, by_value=True):
    try:
        r = ev.sess.send("Runtime.evaluate",
                         {"expression": expr, "returnByValue": by_value, "awaitPromise": False})
        if "exceptionDetails" in r:
            return None
        return r.get("result", {}).get("value")
    except Exception:
        return None


out = {"label": LABEL, "url": URL, "port": PORT}

# ---- P1 navigate + gate handling -------------------------------------------
navigate(ev, engine, URL)

DISMISS_JS = r"""(function(){
  var sels = ['#onetrust-accept-btn-handler','#didomi-notice-agree-button',
    '.didomi-continue-without-agreeing','#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
    '#CybotCookiebotDialogBodyButtonAccept','.cky-btn-accept','[data-testid=accept-all]',
    'button[id*=accept i]','button[class*=accept i]','button[aria-label*=accept i]'];
  for (var i=0;i<sels.length;i++){
    try{var el=document.querySelector(sels[i]);
      if(el && el.offsetParent!==null){el.click(); return sels[i];}}catch(e){}
  }
  // text-based fallback
  var btns=[].slice.call(document.querySelectorAll('button,a[role=button]'));
  for (var j=0;j<btns.length;j++){
    var t=(btns[j].textContent||'').trim().toLowerCase();
    if(/^(accept all|accept|agree|i agree|got it|allow all|ok)$/.test(t) && btns[j].offsetParent!==null){
      btns[j].click(); return 'text:'+t;}
  }
  return null;})();"""

OVERLAY_JS = r"""(function(){
  var k=['onetrust','didomi','cookiebot','cky-','cookie-consent','consent','gdpr'];
  var all=[].slice.call(document.querySelectorAll('div,section,aside'));
  for(var i=0;i<all.length;i++){var id=(all[i].id||'')+' '+(all[i].className||'');id=(''+id).toLowerCase();
    for(var j=0;j<k.length;j++){if(id.indexOf(k[j])>=0 && all[i].offsetParent!==null){return true;}}}
  return false;})();"""

LOADER_JS = r"""(function(){
  var sels=['[class*=loader i]','[id*=loader i]','[class*=preload i]','[class*=loading i]'];
  for(var i=0;i<sels.length;i++){var els=document.querySelectorAll(sels[i]);
    for(var j=0;j<els.length;j++){var e=els[j];
      if(e.offsetParent!==null){var r=e.getBoundingClientRect();
        if(r.width>50 && r.height>50) return true;}}}
  return false;})();"""

out["had_overlay"] = bool(rt(OVERLAY_JS))
dismissed = rt(DISMISS_JS)
out["dismissed"] = dismissed
if dismissed:
    time.sleep(1.2)

# hydration poll: node-count stable + readyState complete + loader gone
curve, prev, stable, t0, loader_seen = [], -1, 0, time.time(), False
while time.time() - t0 < 24:
    n = rt("document.querySelectorAll('*').length") or 0
    ready = rt("document.readyState") == "complete"
    loader = bool(rt(LOADER_JS))
    loader_seen = loader_seen or loader
    curve.append(n)
    if n == prev and n > 10 and ready and not loader:
        stable += 1
        if stable >= 3:
            break
    else:
        stable = 0
    prev = n
    time.sleep(0.5)
time.sleep(1.5)
out["loader_waited"] = loader_seen
out["t_hydrate_s"] = round(time.time() - t0, 1)
out["hydration_curve"] = curve

# ---- P2 characterize (TRUTH) ----------------------------------------------
out["final_url"] = rt("location.href")
out["title"] = (rt("document.title") or "")[:80]
out["hydrated_nodes"] = rt("document.querySelectorAll('*').length")
out["scrollH"] = rt("document.documentElement.scrollHeight")
out["viewport"] = rt("({w:innerWidth,h:innerHeight,dpr:devicePixelRatio})")

out["arch"] = rt(r"""(function(){
  var pushOverridden = history.pushState.toString().indexOf('[native code]')<0;
  return {
    next:!!window.__NEXT_DATA__, nuxt:!!window.__NUXT__,
    gatsby:!!document.querySelector('#___gatsby'),
    remix:!!window.__remixContext, sveltekit:!!window.__sveltekit_dev||!!document.querySelector('[data-sveltekit-hydrate]'),
    astro:!!document.querySelector('astro-island'),
    framer:!!(window.__framer__||document.querySelector('[data-framer-name],[id^=__framer]')),
    react:!!(document.querySelector('#__next,#root,[data-reactroot]')||window.React),
    vue:!!window.__VUE__,
    client_router: pushOverridden,
    a_tags: document.querySelectorAll('a[href]').length
  };})();""")

out["substrate"] = rt(r"""(function(){
  var vw=innerWidth*innerHeight;
  var cv=[].slice.call(document.querySelectorAll('canvas'));
  var carea=0, cmax=0, webgl=0;
  cv.forEach(function(c){var r=c.getBoundingClientRect();var a=Math.max(0,r.width)*Math.max(0,r.height);
    carea+=a; if(a>cmax)cmax=a;
    try{if(c.getContext('webgl2')||c.getContext('webgl'))webgl++;}catch(e){}});
  var vids=[].slice.call(document.querySelectorAll('video'));
  var vbg=vids.filter(function(v){var r=v.getBoundingClientRect();
    return (v.autoplay||v.loop) && r.width*r.height > vw*0.25;}).length;
  return {canvas:cv.length, webgl_canvas:webgl,
    canvas_area_ratio: vw? +(carea/vw).toFixed(2):0,
    max_canvas_area_ratio: vw? +(cmax/vw).toFixed(2):0,
    video:vids.length, video_bg:vbg,
    iframe:document.querySelectorAll('iframe').length,
    img:document.querySelectorAll('img').length, svg:document.querySelectorAll('svg').length};})();""")

# virtualization: scroll to bottom in steps, remeasure
rt("window.scrollTo(0, document.body.scrollHeight)")
time.sleep(0.6)
rt("window.scrollTo(0, document.body.scrollHeight)")
time.sleep(0.8)
out["after_scroll"] = rt("({nodes:document.querySelectorAll('*').length, scrollH:document.documentElement.scrollHeight})")
rt("window.scrollTo(0,0)"); time.sleep(0.3)

out["anim"] = rt(r"""(function(){
  var ga=[]; try{ga=document.getAnimations();}catch(e){}
  var props={}, running=0;
  ga.forEach(function(a){try{
    if(a.playState==='running')running++;
    var kf=a.effect&&a.effect.getKeyframes?a.effect.getKeyframes():[];
    kf.forEach(function(f){for(var k in f){if(['offset','composite','computedOffset','easing'].indexOf(k)<0)props[k]=1;}});
  }catch(e){}});
  var st=0; try{if(window.gsap&&window.gsap.core&&window.ScrollTrigger)st=window.ScrollTrigger.getAll().length;
    else if(window.ScrollTrigger)st=window.ScrollTrigger.getAll().length;}catch(e){}
  return {
    getAnimations_total: ga.length, running: running,
    animated_props: Object.keys(props),
    gsap: !!window.gsap, scrolltrigger_count: st,
    lottie: !!(window.lottie||document.querySelector('lottie-player,[data-animation-path],[class*=lottie i]')),
    three: !!(window.THREE),
    rive: !!(window.rive||window.Rive),
    splide_swiper: !!(window.Swiper||document.querySelector('.swiper,.splide')),
    marquee: !!document.querySelector('marquee,[class*=marquee i]'),
    css_transition_sample: (function(){var c=0;var els=[].slice.call(document.querySelectorAll('*')).slice(0,400);
      els.forEach(function(e){var t=getComputedStyle(e).transitionDuration;if(t&&t!=='0s')c++;});return c;})()
  };})();""")

out["state"] = rt(r"""(function(){
  var fixed=[].slice.call(document.querySelectorAll('*')).slice(0,600).filter(function(e){
    return getComputedStyle(e).position==='fixed';});
  return {
    custom_cursor: !!document.querySelector('[class*=cursor i],[id*=cursor i]'),
    aria_expanded: document.querySelectorAll('[aria-expanded]').length,
    aria_haspopup: document.querySelectorAll('[aria-haspopup]').length,
    dialogs: document.querySelectorAll('dialog,[role=dialog],[aria-modal=true]').length,
    fixed_overlays: fixed.length,
    internal_links: (function(){try{var a=[].slice.call(document.querySelectorAll('a[href]'));
      return a.filter(function(x){try{return new URL(x.href).origin===location.origin;}catch(e){return false;}}).length;}catch(e){return -1;}})()
  };})();""")

out["tokens_truth"] = rt(r"""(function(){
  var els=[].slice.call(document.querySelectorAll('*')).slice(0,1500);
  var bg={},fg={},ff={},fs={};
  els.forEach(function(e){var s=getComputedStyle(e);
    if(s.backgroundColor&&s.backgroundColor!=='rgba(0, 0, 0, 0)')bg[s.backgroundColor]=1;
    if(s.color)fg[s.color]=1; if(s.fontFamily)ff[s.fontFamily.split(',')[0].replace(/["']/g,'').trim()]=1;
    if(s.fontSize)fs[s.fontSize]=1;});
  return {bg_colors:Object.keys(bg).length, fg_colors:Object.keys(fg).length,
    font_families:Object.keys(ff).slice(0,12), type_scale_count:Object.keys(fs).length};})();""")

# write truth before verbs re-navigate
(OUTDIR / (LABEL + ".partial.json")).write_text(json.dumps(out, default=str, indent=2))

# ---- P3 verb-as-is (skeleton canary; full pipeline only where signal) ------
def run_verb(name, extra):
    skpath = str(OUTDIR / (LABEL + "_" + name + ".out"))
    cmd = [sys.executable, name + ".py", "--browser", "chrome", "--cdp-port", str(PORT), "--url", URL] + extra
    try:
        r = subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True, timeout=90)
        return {"rc": r.returncode, "stdout_tail": (r.stdout or "")[-400:], "stderr_tail": (r.stderr or "")[-200:]}
    except subprocess.TimeoutExpired:
        return {"rc": "timeout"}
    except Exception as e:
        return {"rc": "err", "msg": str(e)[:160]}

verb = {}
skf = str(OUTDIR / (LABEL + "_sk.json"))
verb["skeleton"] = run_verb("web_skeleton", ["--out", skf])
try:
    skj = json.loads(Path(skf).read_text())
    verb["skeleton"]["nodes"] = len(skj.get("nodes", []))
    verb["skeleton"]["page_h"] = skj.get("page", {}).get("h")
    verb["skeleton"]["bytes"] = len(Path(skf).read_text())
except Exception:
    verb["skeleton"]["nodes"] = 0

sk_nodes = verb["skeleton"].get("nodes", 0) or 0
# full pipeline only where skeleton found real signal
if sk_nodes > 50:
    tokf = str(OUTDIR / (LABEL + "_tok.json"))
    verb["tokens"] = run_verb("web_tokens", ["--out", tokf])
    bundf = str(OUTDIR / (LABEL + "_bundle"))
    try:
        b = subprocess.run([sys.executable, "bundle_writer.py", "--skeleton", skf, "--tokens", tokf,
                            "--out", bundf], cwd=SCRIPTS, capture_output=True, text=True, timeout=60)
        verb["bundle"] = {"rc": b.returncode, "stdout_tail": (b.stdout or "")[-300:]}
    except Exception as e:
        verb["bundle"] = {"rc": "err", "msg": str(e)[:140]}
else:
    verb["tokens"] = {"skipped": "skeleton<50 nodes — no signal (see attribution)"}
    verb["bundle"] = {"skipped": True}

out["verb"] = verb

# ---- P4 scorecard + attribution -------------------------------------------
sub = out.get("substrate") or {}
car = sub.get("canvas_area_ratio", 0) or 0
hyd = out.get("hydrated_nodes") or 0
asc = out.get("after_scroll") or {}
virt_delta = (asc.get("nodes", hyd) - hyd) if hyd else 0

# --- two INDEPENDENT axes (advisor #2: never collapse) ----------------------
# Axis 1: substrate blindness — what % of the page is canvas/WebGL (un-reproducible
#         by DOM capture regardless of timing). Always reported.
substrate_blind = int(min(car, 1.0) * 100)
intro_loader_gate = bool(out["loader_waited"] and out["t_hydrate_s"] >= 24)

# Axis 2: DOM-structure shortfall — given the DOM that DOES exist, did the verb get it?
ratio = round(sk_nodes / hyd, 3) if hyd else None
if hyd and hyd < 120 and sk_nodes >= 0.5 * hyd:
    shortfall = "ok-small-page"
elif ratio is not None and ratio >= 0.6:
    shortfall = "ok-domcaptured"
elif sk_nodes <= 5 and out["had_overlay"] and not out["dismissed"]:
    shortfall = "consent-wall"
elif sk_nodes <= 5 and not (hyd and hyd > 200):
    shortfall = "empty-or-crash"
elif out["t_hydrate_s"] >= 12 or intro_loader_gate:
    shortfall = "hydration-timing-G1"   # real DOM existed but verb's 2s settle was too early
elif car >= 0.5:
    shortfall = "content-lives-in-canvas-G5"
elif virt_delta > 0.3 * (hyd or 1):
    shortfall = "virtualization-G2"
else:
    shortfall = "partial-unattributed"

# Axis 3: motion — bundle assembly succeeding does NOT mean motion captured.
# This canary runs NO web_anim/web_flipbook, so motion_rows is always 0; getAnimations
# truth (ga + css_transition_sample + gsap/scrolltrigger) is what a faithful repro needs.
an = out.get("anim") or {}
motion_demand = {
    "getAnimations": an.get("getAnimations_total"),
    "css_transitions": an.get("css_transition_sample"),
    "scroll_driven": (an.get("scrolltrigger_count") or 0) > 0 or an.get("gsap"),
    "lottie": an.get("lottie"), "three": an.get("three"),
    "canvas_motion_unmeasurable": car >= 0.3,
}

out["scorecard"] = {
    "arch_detected": out["arch"],
    "structure_capture_ratio": ratio,
    "verb_nodes": sk_nodes, "hydrated_nodes": hyd,
    "substrate_blind_pct": substrate_blind,        # axis 1
    "structure_shortfall_cause": shortfall,         # axis 2
    "intro_loader_gate": intro_loader_gate,
    "virtualization_delta_nodes": virt_delta,
    "bundle_assembled": (out["verb"].get("bundle", {}).get("rc") == 0),
    "motion_captured_by_canary": False,             # axis 3: canary binds no motion by design
    "motion_demand": motion_demand,
}
gap = shortfall

(OUTDIR / (LABEL + ".json")).write_text(json.dumps(out, default=str, indent=2))
(OUTDIR / (LABEL + ".partial.json")).unlink(missing_ok=True)

sc = out["scorecard"]
print("[%s] %s" % (LABEL, out["final_url"]))
print("  arch: next=%s nuxt=%s framer=%s client_router=%s | t_hydrate=%ss overlay=%s/dismiss=%s loader=%s" % (
    out["arch"].get("next"), out["arch"].get("nuxt"), out["arch"].get("framer"),
    out["arch"].get("client_router"), out["t_hydrate_s"], out["had_overlay"], out["dismissed"], out["loader_waited"]))
print("  substrate: canvas=%s webgl=%s area_ratio=%s vbg=%s | svg=%s img=%s" % (
    sub.get("canvas"), sub.get("webgl_canvas"), car, sub.get("video_bg"), sub.get("svg"), sub.get("img")))
print("  TRUTH nodes=%s scrollH=%s | after_scroll=%s (virt_delta=%s)" % (
    hyd, out["scrollH"], asc.get("nodes"), virt_delta))
print("  anim: ga=%s gsap=%s ST=%s lottie=%s three=%s css_trans=%s | props=%s" % (
    out["anim"].get("getAnimations_total"), out["anim"].get("gsap"), out["anim"].get("scrolltrigger_count"),
    out["anim"].get("lottie"), out["anim"].get("three"), out["anim"].get("css_transition_sample"),
    out["anim"].get("animated_props")))
print("  state: cursor=%s expand=%s dialogs=%s fixed=%s ilinks=%s" % (
    out["state"].get("custom_cursor"), out["state"].get("aria_expanded"), out["state"].get("dialogs"),
    out["state"].get("fixed_overlays"), out["state"].get("internal_links")))
print("  VERB skeleton nodes=%s (rc=%s) | capture_ratio=%s | tokens=%s bundle_rc=%s" % (
    sk_nodes, verb["skeleton"].get("rc"), sc["structure_capture_ratio"],
    "run" if sk_nodes > 50 else "skip", out["verb"].get("bundle", {}).get("rc")))
print("  >>> SUBSTRATE_BLIND=%s%% | STRUCTURE_SHORTFALL=%s (ratio=%s) | MOTION_demand=%s canvas_unmeasurable=%s" % (
    sc["substrate_blind_pct"], shortfall, sc["structure_capture_ratio"],
    {k: v for k, v in motion_demand.items() if v}, motion_demand["canvas_motion_unmeasurable"]))
ev.close()
