#!/usr/bin/env python3
"""Measure scroll-driven animation easing with CERTIFIED determinism.

Modern sites bind CSS properties to scroll position (Lenis / GSAP-scrub /
CSS scroll-driven): `prop = f(scrollY)`. Sampling during a live scroll
measures `f(smoothedScroll)` with inertial lag + frame-drop jank — wrong.
This tool instead sets scrollY *statically*, lets the smooth-scroll lib
settle, and reads the computed style, recovering `f(scrollY)` exactly.

The determinism is *proven*, not assumed (see `_anim_core`): an easing fit is
emitted ONLY when scrollY held AND the property reproduces on revisit
(scroll-scrubbed, not time-based) AND the curve is monotonic AND matches a
standard easing tightly. Channels that fail are reported `certified: false`
with a reason — the tool never guesses.

The method is engine-agnostic: it needs only (1) set an exact scroll offset and
(2) read the rendered transform. Three transports, all certified identically:
  - Chrome / Chromium (host) over CDP  — default.
  - Safari (host) and Mobile Safari on a booted iOS sim over WebDriver.
  - Chrome / debuggable WebView in an Android emulator over adb-forwarded CDP.

Usage:
  web_anim.py                                   # host Chrome, auto-discover
  web_anim.py --selector "h1" --steps 32        # measure a specific element
  web_anim.py --range 0:1400 --detect-only      # report the animation stack
  web_anim.py --android --url https://site      # emulator Chrome (adb forward)
  web_anim.py --ios --url https://site          # Mobile Safari on booted sim
  web_anim.py --cdp-port 9223 --url https://x   # any pre-forwarded CDP endpoint
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_path, emit_json, out_path
from _web_eval import resolve_web_eval, navigate, add_transport_args
from _anim_core import vecs_close, analyze_movers, concentrate_bands, CHANNELS
from motion_adapter import motion_summary

# In-page probe namespace: decompose transforms + accumulate scroll deltas
# without ever shipping the full element table back over the wire.
_INSTALL = r"""
(()=>{const P={};
 P.dec=function(el){var cs=getComputedStyle(el),m=cs.transform,
    tx=0,ty=0,sx=1,sy=1,rot=0,tz=0,rotX=0,rotY=0,D=180/Math.PI;
  if(m&&m!=='none'){var p=m.match(/matrix(3d)?\(([^)]+)\)/);
   if(p){var a=p[2].split(',').map(Number);
    if(p[1]){/* matrix3d, column-major a[0..15] */
     tx=a[12];ty=a[13];tz=a[14];
     sx=Math.hypot(a[0],a[1],a[2]);sy=Math.hypot(a[4],a[5],a[6]);
     rot=Math.atan2(a[1],a[0])*D;        /* in-plane (Z) rotation */
     /* single-axis tilt extraction (ambiguous for combined 3D rotations -> only
        certified for single-axis depth motion; combined reads approximate) */
     rotX=Math.atan2(a[6],a[10])*D;       /* rotation about X */
     rotY=Math.atan2(-a[2],a[0])*D;       /* rotation about Y */
    }else{tx=a[4];ty=a[5];sx=Math.hypot(a[0],a[1]);sy=Math.hypot(a[2],a[3]);
     rot=Math.atan2(a[1],a[0])*D;}}}
  return [tx,ty,sx,sy,rot,parseFloat(cs.opacity),tz,rotX,rotY];};
 P.all=[].slice.call(document.querySelectorAll('body *'));
 P.delta=new Array(P.all.length).fill(0);P.base=null;
 P.snapBase=function(){P.base=P.all.map(P.dec);return P.all.length;};
 P.accum=function(){var b=P.base;for(var i=0;i<P.all.length;i++){var c=P.dec(P.all[i]),o=b[i];
   var d=Math.max(Math.abs(c[0]-o[0]),Math.abs(c[1]-o[1]),Math.abs(c[2]-o[2])*100,
                  Math.abs(c[3]-o[3])*100,Math.abs(c[4]-o[4]),Math.abs(c[5]-o[5])*200,
                  Math.abs(c[6]-o[6]),Math.abs(c[7]-o[7]),Math.abs(c[8]-o[8]));
   if(d>P.delta[i])P.delta[i]=d;}return 0;};
 P.meta=function(el,r){el.setAttribute('data-pa',r);
   var c=(el.className&&el.className.toString().trim().split(/\s+/)[0])||'';
   /* meta is read at pick()/tagSel() time, when the page may be parked mid-
      animation, so getBoundingClientRect carries the live tx/ty. Subtract the
      decoded transform to recover the REST (layout) page coords — the same CSS
      frame web_skeleton emits, so match_motion can join anchors to nodes.
      absX is the REST CENTER-x (match_motion compares node center-x); absY the
      REST top edge (compared to node bbox.y top). Exact for translate;
      approximate under scale (width is post-transform) — fine for ±band bind. */
   var d=P.dec(el),b=el.getBoundingClientRect();
   return {rank:r,sel:el.tagName.toLowerCase()+(c?'.'+c:''),tag:el.tagName,
           absY:Math.round(b.top+window.scrollY-d[1]),
           absX:Math.round(b.left+window.scrollX-d[0]+b.width/2),
           txt:(el.textContent||'').trim().slice(0,32)};};
 P.pick=function(eps,K){var idx=[];for(var i=0;i<P.delta.length;i++)if(P.delta[i]>eps)idx.push(i);
   idx.sort(function(a,b){return P.delta[b]-P.delta[a];});idx=idx.slice(0,K);
   return idx.map(function(i,r){var m=P.meta(P.all[i],r);m.score=Math.round(P.delta[i]);return m;});};
 P.tagSel=function(sel,K){var els=[].slice.call(document.querySelectorAll(sel)).slice(0,K);
   return els.map(function(el,r){return P.meta(el,r);});};
 P.read=function(){var els=[].slice.call(document.querySelectorAll('[data-pa]'));
   els.sort(function(a,b){return (+a.getAttribute('data-pa'))-(+b.getAttribute('data-pa'));});
   return {y:Math.round(window.scrollY),
           m:els.map(P.dec).map(function(v){return v.map(function(x){return Math.round(x*1000)/1000;});})};};
 P.cleanup=function(){document.querySelectorAll('[data-pa]').forEach(function(e){e.removeAttribute('data-pa');});};
 window.__pa=P;return P.all.length;})()
"""

_DETECT = r"""
(()=>{return JSON.stringify({
 url:location.href,
 scrollH:document.documentElement.scrollHeight,innerH:innerHeight,
 lenis:!!(window.Lenis||window.lenis||document.querySelector('.lenis,[class*="lenis"]')),
 gsap:(window.gsap&&gsap.version)||null,
 scrollTrigger:!!(window.ScrollTrigger||(window.gsap&&gsap.core&&gsap.core.globals&&gsap.core.globals().ScrollTrigger)),
 locomotive:!!(window.LocomotiveScroll||document.querySelector('[data-scroll-container],[data-scroll]')),
 framer:!!(document.querySelector('[data-framer-name],[data-framer-component-type]')||[].some.call(document.scripts,function(s){return /framer/i.test(s.src);})),
 react:!!(window.__NEXT_DATA__||document.querySelector('#__next,[data-reactroot]')),
 scrollBehavior:getComputedStyle(document.documentElement).scrollBehavior,
});})()
"""


# The eval transport (`ev(expr) -> value`) and the resolver that picks one for a
# given flag set live in `_web_eval`, shared verbatim with `web_eval` so the two
# verbs cannot drift apart in which engine they target.


def _ev(ev, expr):
    return ev.ev(expr)


def _set_scroll(ev, y):
    _ev(ev, "(function(y){var d=document.documentElement;d.style.scrollBehavior='auto';"
            "document.body.style.scrollBehavior='auto';window.scrollTo(0,y);"
            "return Math.round(window.scrollY);})(%d)" % y)


def _wait_scrollable(ev, max_wait=15.0, poll=0.5, stable_needed=3):
    """Poll until the page's scroll height stabilizes (SPA hydration / late GSAP
    builds the tall page AFTER the load event). Returns the settled dict
    {"sh": scrollHeight, "ih": innerHeight}.

    The settle gate requires sh stable AND sh > ih: a pre-hydration shell whose
    scrollHeight==innerHeight is "stable" from t=0 (e.g. for the ~6s a late build
    takes), so gating on stability alone would false-positive and return the
    shell height -> empty range. Requiring sh > ih makes us keep polling through
    that window until the page is actually scrollable.

    Consequence (intentional, do NOT "fix" with an early exit): a page that is
    genuinely non-natively-scrollable (sh<=ih forever, e.g. wrapper-virtualized
    scroll) never satisfies the gate and burns the full max_wait before returning
    sh≈ih -> caller's empty-range bail (the deferred virtual case). We cannot
    distinguish 'still hydrating' from 'truly virtual' without waiting, so an
    early exit on stable-but-not-scrollable would re-break the late-build case."""
    last, stable = -1, 0
    deadline = time.time() + max_wait
    while time.time() < deadline:
        d = _ev(ev, "({sh:document.documentElement.scrollHeight,ih:innerHeight})")
        if d["sh"] == last and d["sh"] > d["ih"]:
            stable += 1
            if stable >= stable_needed:
                return d
        else:
            stable = 0
        last = d["sh"]
        time.sleep(poll)
    return d


def _read_settled(ev, y, tol, timeout, poll=0.06):
    """Set scroll, then poll until scrollY==target AND transforms stop changing
    between consecutive reads (smooth-scroll driver has converged). Returns the
    read dict with an added 'settled' bool — we read the converged f(scrollY),
    never a frame mid-glide."""
    _set_scroll(ev, y)
    end = time.monotonic() + timeout
    prev = None
    while True:
        r = _ev(ev, "window.__pa.read()")
        ok_y = abs(r["y"] - y) <= tol
        if ok_y and prev is not None and vecs_close(r["m"], prev["m"]):
            r["settled"] = True
            return r
        prev = r
        if time.monotonic() > end:
            r["settled"] = ok_y
            return r
        time.sleep(poll)


def _sweep(ev, step_ys, movers, args, settle):
    """Run one static scroll sweep over step_ys; returns
    (rows_m, ys, mid_m, revisit, mid_idx, drift_ok, max_drift, unsettled).

    rows_m is the per-step list of per-mover vectors (rows_m[step][mover]); ys is
    the list of *target* scroll offsets (not the actual settled scrollY). __pa is
    assumed already installed and the movers already tagged — this helper neither
    installs nor cleans up the in-page probe, so movers stay index-stable across
    sweeps and the merge can match them by index."""
    mid_idx = len(step_ys) // 2
    rows = []
    max_drift = 0.0
    unsettled = 0
    for y in step_ys:
        r = _read_settled(ev, y, args.tol, timeout=settle)
        max_drift = max(max_drift, abs(r["y"] - y))
        if not r["settled"]:
            unsettled += 1
        rows.append((y, r["y"], r["m"]))

    # ---- reproducibility probe: revisit the mid scroll position and converge
    # again. A scroll-scrubbed prop returns to the same value (function of
    # scroll); a time-based tween/loop does not. Both reads are converged, so
    # this is immune to sub-pixel scroll jitter.
    revisit = _read_settled(ev, step_ys[mid_idx], args.tol, timeout=settle)["m"]
    mid_m = rows[mid_idx][2]

    drift_ok = max_drift <= args.tol and unsettled == 0
    ys = [r[0] for r in rows]
    rows_m = [r[2] for r in rows]
    return rows_m, ys, mid_m, revisit, mid_idx, drift_ok, max_drift, unsettled


def _merge_prefer_certified(a, b):
    """Per mover/channel keep the entry that is certified (or has all-certified
    segments); else keep the finer-sweep (b) entry.

    a and b are analyze_movers outputs over the SAME movers list in the SAME
    order (matched by index). For each channel key present in either, keep a's
    entry if it is certified (the core already flips certified=True when every
    segment certifies), otherwise take b's entry (the finer sweep). Returns a
    merged list in the shape analyze_movers returns."""
    merged = []
    for mi in range(len(a)):
        ea = a[mi]
        eb = b[mi] if mi < len(b) else {"channels": {}}
        ch_a = ea.get("channels", {})
        ch_b = eb.get("channels", {})
        out_ch = {}
        for key in set(ch_a) | set(ch_b):
            ca = ch_a.get(key)
            cb = ch_b.get(key)
            if ca is not None and ca.get("certified"):
                out_ch[key] = ca
            elif cb is not None:
                out_ch[key] = cb
            else:
                out_ch[key] = ca
        # recompute dominant from the merged channels (prefer a's if still valid)
        dom = ea.get("dominant")
        if dom not in out_ch:
            dom = eb.get("dominant") if eb.get("dominant") in out_ch else (
                next(iter(out_ch), None))
        merged.append({**ea, "dominant": dom, "channels": out_ch})
    return merged


def main() -> int:
    p = argparse.ArgumentParser()
    add_transport_args(p)  # --browser/--url/--android/--ios/--cdp-port/--serial (shared)
    p.add_argument("--selector", help="CSS selector to measure (default: auto-discover movers)")
    p.add_argument("--steps", type=int, default=40, help="static scroll samples (default 40)")
    p.add_argument("--settle", type=int, default=1500,
                   help="ms convergence timeout per step (polls until scrollY+transforms settle)")
    p.add_argument("--range", help="scroll range 'lo:hi' in px (default 0:maxScroll)")
    p.add_argument("--top", type=int, default=48, help="max movers to report")
    p.add_argument("--eps", type=float, default=3.0, help="discovery motion threshold")
    p.add_argument("--tol", type=float, default=2.0, help="max |actualY-targetY| px to certify")
    p.add_argument("--detect-only", action="store_true", help="report stack only, no measurement")
    p.add_argument("--out", help="output JSON path")
    p.add_argument("--zoom-budget", type=int, default=0,
                   help="max refined samples in the adaptive 2nd sweep "
                        "(0 = auto: max(160, steps*8)); raise to cover more bands "
                        "on busy pages at the cost of more CDP round-trips")
    args = p.parse_args()
    if args.zoom_budget <= 0:
        args.zoom_budget = max(160, args.steps * 8)

    # ---- resolve transport (shared with web_eval; one resolver, identical engines) ----
    engine, ev, device = resolve_web_eval(args)

    settle = args.settle / 1000.0
    try:
        # ---- navigate if asked (mandatory for the fresh WebDriver sessions) ----
        if args.url:
            navigate(ev, engine, args.url)

        detect = json.loads(_ev(ev, _DETECT))
        if args.detect_only:
            emit_json({**detect, "engine": engine, "device": device})
            return 0

        ready = _wait_scrollable(ev)
        max_scroll = max(0, int(ready["sh"] - ready["ih"]))
        if args.range:
            lo, hi = (int(x) for x in args.range.split(":"))
        else:
            lo, hi = 0, max_scroll
        if hi <= lo:
            die(f"empty scroll range {lo}:{hi} (page may not scroll)")

        _ev(ev, _INSTALL)

        # ---- discover movers (or tag the user's selector) ----
        if args.selector:
            movers = _ev(ev, "window.__pa.tagSel(%s,%d)" % (json.dumps(args.selector), args.top))
            if not movers:
                die(f"selector matched nothing: {args.selector}")
        else:
            probe_pts = [lo + (hi - lo) * k // 3 for k in range(4)]  # lo, 1/3, 2/3, hi
            _set_scroll(ev, probe_pts[0]); time.sleep(settle)
            _ev(ev, "window.__pa.snapBase()")
            for y in probe_pts[1:]:
                _set_scroll(ev, y); time.sleep(settle)
                _ev(ev, "window.__pa.accum()")
            movers = _ev(ev, "window.__pa.pick(%f,%d)" % (args.eps, args.top))
            if not movers:
                emit_json({**detect, "engine": engine, "device": device, "movers": [],
                           "note": "no scroll-animated elements found in range"})
                return 0

        # ---- measure: static sweep; each read polls to convergence ----
        step_ys = [round(lo + (hi - lo) * i / (args.steps - 1)) for i in range(args.steps)]
        rows_m, ys, mid_m, revisit, mid_idx, drift_ok, max_drift, unsettled = \
            _sweep(ev, step_ys, movers, args, settle)

        # ---- analyze per mover / per channel (engine-agnostic core) ----
        # NOTE: must run while ev/__pa are still alive (before the finally that
        # closes the transport) so the adaptive second sweep below can re-read.
        out_movers = analyze_movers(movers, ys, rows_m, mid_m, revisit, mid_idx,
                                    drift_ok, max_drift, unsettled)

        # ---- adaptive second sweep: the single uniform sweep under-samples
        # narrow ScrollTrigger bands (channels report "no resolvable active range
        # at this sampling"). When that happens (and the user did not pin a
        # --range), re-sweep concentrating samples into the bands where the first
        # sweep saw motion, then merge, preferring certified entries.
        need_zoom = any(
            (e.get("reason") or "").startswith("no resolvable active range")
            for m in out_movers for e in m["channels"].values())
        if need_zoom and not args.range:
            # The second sweep is an OPTIONAL refinement; it must never discard the
            # already-valid first-sweep result. Guard the whole block so a transport
            # hiccup mid-refine can't abort a run whose first sweep succeeded.
            try:
                # Per-(mover,channel) motion: each uncertified channel's own
                # |delta| series. concentrate_bands then guarantees each channel's
                # OWN band a dense budget (the global motion_per_step diluted narrow
                # bands on multi-mover pages — see p1-real-site-scroll-certification).
                motion_per_channel = []
                for mi in range(len(movers)):
                    chans = out_movers[mi].get("channels", {})
                    for c, e in chans.items():
                        if e.get("certified"):
                            continue
                        ci = CHANNELS.index(c)
                        arr = [0.0]
                        for si in range(1, len(rows_m)):
                            a = rows_m[si][mi] if mi < len(rows_m[si]) else []
                            b = rows_m[si - 1][mi] if mi < len(rows_m[si - 1]) else []
                            arr.append(abs(a[ci] - b[ci]) if ci < len(a) and ci < len(b) else 0.0)
                        motion_per_channel.append(arr)
                refined_ys = concentrate_bands(ys, motion_per_channel,
                                               k_per_band=24,
                                               max_total=args.zoom_budget)
                (rows_m2, ys2, mid_m2, revisit2, mid_idx2,
                 drift_ok2, max_drift2, unsettled2) = _sweep(ev, refined_ys, movers, args, settle)
                out2 = analyze_movers(movers, ys2, rows_m2, mid_m2, revisit2, mid_idx2,
                                      drift_ok2, max_drift2, unsettled2)
                out_movers = _merge_prefer_certified(out_movers, out2)
            except Exception as e:
                print("probe-runner: adaptive second sweep skipped (%s)" % e, file=sys.stderr)
    finally:
        try:
            # single IIFE so the same expr is valid under both CDP (statements
            # ok) and WebDriver (wrapped as `return (expr)` — needs one expr).
            _ev(ev, "(function(){try{window.__pa&&window.__pa.cleanup();"
                    "delete window.__pa;}catch(e){}return 1;})()")
        except Exception:
            pass
        ev.close()

    # out_movers / ys / rows_m were produced inside the try (above) while the
    # transport was still alive — the adaptive second sweep needs ev open, so the
    # analysis can no longer run after the finally. The payload's series reflects
    # the FIRST (uniform) sweep; only out_movers is merged with the finer sweep.
    n = len(movers)

    payload = {
        "stack": detect, "engine": engine, "device": device,
        "scrollRange": [lo, hi], "steps": args.steps, "settleMs": args.settle,
        "certifiedDeterministic": drift_ok, "maxDriftPx": round(max_drift, 1),
        "movers": out_movers,
        "series": {"scrollY": ys,
                   "perMover": [[rows_m[s][mi] if mi < len(rows_m[s]) else None
                                 for s in range(len(rows_m))] for mi in range(n)]},
        # consistent per-axis best-reading block for direct consumers (agents).
        # Surfaces {easing, amplitude, rms, window, confidence} per axis without
        # parsing the raw movers/channels shape. klass="scroll": no duration
        # (prop = f(scrollY) is timeless); window = activeScroll. See
        # motion_adapter.motion_summary for the contract.
        "motion_summary": motion_summary({"movers": out_movers}, "scroll"),
    }
    out = Path(args.out) if args.out else out_path("anim", "json")
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False))

    # concise human summary to stdout
    print("engine: %s (%s)" % (engine, device))
    print("stack: " + (", ".join(k for k in
          ("lenis", "scrollTrigger", "locomotive", "framer", "react") if detect.get(k)) or "(none detected)"))
    print("certified-deterministic: %s (maxDrift %.1fpx, tol %.1f)" %
          (drift_ok, max_drift, args.tol))
    for m in out_movers:
        absy = m.get("absY")
        print("  [%s] %r%s" % (m["sel"], (m.get("txt") or "")[:24],
                               "  @y≈%d" % absy if absy is not None else ""))
        for c, e in m["channels"].items():
            ez = e.get("easing")
            segs = e.get("segments")
            if e["certified"] and ez:
                tag = "%s rms=%.3f  CERTIFIED" % (ez["name"], ez["rms"])
            elif e["certified"] and segs:               # certified via per-segment fits
                tag = "%d segments CERTIFIED [%s]" % (
                    len(segs), ", ".join(s["easing"]["name"] for s in segs))
            elif ez:
                tag = "%s rms=%.3f  UNCERTIFIED: %s" % (ez["name"], ez["rms"], e.get("reason", ""))
            elif segs:
                tag = "%d segments (%d certified)  UNCERTIFIED: %s" % (
                    len(segs), sum(1 for s in segs if s.get("certified")), e.get("reason", ""))
            else:
                tag = "UNCERTIFIED: " + e.get("reason", "")
            print("    %-3s %s→%s  %s" % (c, e["from"], e["to"], tag))
    any_cert = any(e["certified"] for m in out_movers for e in m["channels"].values())
    if out_movers and not any_cert and not args.selector:
        print("tip: nothing certified at this coarse full-page sampling. Re-run "
              "targeting one section, e.g. --range <@y-200>:<@y+900> --steps 28")
    emit_path(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
