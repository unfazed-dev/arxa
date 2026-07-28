#!/usr/bin/env python3
"""web_flipbook -- frame-based motion recovery for STATIC-viewport, time/event
animations (menu open, entrance, fade) that web_anim cannot scroll-certify.

Captures a frame sequence of the animation and recovers its motion law
(tx/ty/scale/opacity over time) by tracking the element across frames -- content
independent, so a clone with different images is certified by motion SHAPE.

Shares `_web_eval`'s transport resolver with web_anim/web_eval (in sync) and
`_flipbook.analyze_frames` (shared with the native verb). Two capture modes:

  scrub    -- if the element's animation is WAAPI (framer-motion, CSS), pause it
              and step its timeline: deterministic, unlimited time resolution.
  realtime -- pure-rAF JS animations aren't scrubbable: poll-capture during play.

Triggers: --reload (entrance), --click <sel> (real CDP Input, fires framer's
pointer handlers where el.click() does not). getAnimations() is read as an exact
ground-truth cross-check (web only). A second capture pass gates reproducibility.

NOTE: scroll-scrubbed animations belong on web_anim (a fixed capture window on a
scrolling page measures scroll-through, not the element transform).
"""
from __future__ import annotations

import argparse
import base64
import json
import time
from pathlib import Path

from _common import die, emit_json
from _web_eval import resolve_web_eval, navigate, add_transport_args
from _flipbook import analyze_frames
from motion_adapter import motion_summary

GT_JS = """(()=>{const e=document.querySelector(%s);if(!e)return null;
  const as=e.getAnimations({subtree:true});if(!as.length)return null;
  return as.map(a=>{const ct=a.effect.getComputedTiming();const tm=a.effect.getTiming();
    let kf=[];try{kf=a.effect.getKeyframes().map(k=>({offset:k.computedOffset,easing:k.easing,
      transform:k.transform,opacity:k.opacity}));}catch(e){}
    return {duration:ct.duration,delay:tm.delay,easing:tm.easing,keyframes:kf};});})()"""

BBOX_JS = """(()=>{const e=document.querySelector(%s);if(!e)return null;
  const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};})()"""

CENTER_JS = """(()=>{const e=document.querySelector(%s);if(!e)return null;
  const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()"""

GRAB_JS = """(()=>{const e=document.querySelector(%s);if(!e)return null;
  const as=e.getAnimations({subtree:true});if(!as.length)return null;
  window.__fb=as;let d=0;for(const a of as){a.pause();
    const dd=a.effect.getComputedTiming().duration;if(dd>d)d=dd;}
  return {n:as.length,dur:d};})()"""


def real_click(ev, cx, cy):
    for t in ("mouseMoved", "mousePressed", "mouseReleased"):
        p = {"type": t, "x": cx, "y": cy}
        if t != "mouseMoved":
            p.update(button="left", clickCount=1)
        ev.sess.send("Input.dispatchMouseEvent", p)
        time.sleep(0.02)


def main() -> int:
    p = argparse.ArgumentParser()
    add_transport_args(p)
    p.add_argument("--selector", required=True, help="element to track")
    p.add_argument("--click", help="selector to real-click as the trigger")
    p.add_argument("--reload", action="store_true", help="reload, then capture entrance")
    p.add_argument("--entering", action="store_true",
                   help="element is absent in frame 0 (template from the settled frame)")
    p.add_argument("--steps", type=int, default=24, help="scrub-mode timeline samples")
    p.add_argument("--seconds", type=float, default=1.5, help="realtime capture window")
    p.add_argument("--fps", type=float, default=20, help="realtime capture rate")
    p.add_argument("--settle", type=int, default=150, help="ms after trigger before locating the animation")
    p.add_argument("--scrub-settle", type=float, default=0.12, dest="scrub_settle",
                   help="seconds to let the compositor paint after each scrub seek "
                        "(raise on slow remote/emulator compositors)")
    p.add_argument("--scale", action="store_true", help="also recover the scale channel (ORB+affine)")
    p.add_argument("--no-repro", action="store_true", help="skip the reproducibility second pass")
    p.add_argument("--out", default=None)
    args = p.parse_args()

    engine, ev, device = resolve_web_eval(args)
    if not hasattr(ev, "sess"):
        die("web_flipbook needs a CDP transport (chrome host / --android / --cdp-port). "
            "Safari/iOS-web and native apps use the native flipbook verb.")
    try:
        if args.url:
            navigate(ev, engine, args.url)
        dpr = ev.ev("window.devicePixelRatio") or 1.0
        vw = int(ev.ev("window.innerWidth"))
        vh = int(ev.ev("window.innerHeight"))
        sel = json.dumps(args.selector)
        stamp = int(time.time())

        def shot(outdir, i):
            data = ev.sess.send("Page.captureScreenshot", {
                "format": "png",
                "clip": {"x": 0, "y": 0, "width": vw, "height": vh, "scale": 1},
                "captureBeyondViewport": False})["data"]
            pth = str(Path(outdir) / ("f%05d.png" % i))
            with open(pth, "wb") as f:
                f.write(base64.b64decode(data))
            return pth

        def capture(tag):
            outdir = Path(args.out or "/tmp/probe-runner") / ("flipbook-%d-%s" % (stamp, tag))
            outdir.mkdir(parents=True, exist_ok=True)
            if args.reload:
                ev.ev("location.reload()")
                time.sleep(2.0)
            if args.click:
                c = ev.ev(CENTER_JS % json.dumps(args.click))
                if not c:
                    die("trigger selector not found: " + args.click)
                real_click(ev, c["x"], c["y"])
            time.sleep(args.settle / 1000.0)
            grab = ev.ev(GRAB_JS % sel)
            if grab and grab.get("dur", 0) and grab["dur"] > 0:
                dur = grab["dur"]
                paths, xs = [], []
                for i in range(args.steps):
                    ct = dur * i / (args.steps - 1)
                    ev.ev("window.__fb.forEach(a=>a.currentTime=%f);" % ct)
                    time.sleep(args.scrub_settle)
                    paths.append(shot(outdir, i))
                    xs.append(ct)
                ev.ev("window.__fb.forEach(a=>{try{a.play();}catch(e){}});")
                return paths, xs, "scrub"
            # realtime fallback for pure-rAF animations
            t0 = ev.ev("performance.now()")
            paths, xs, i = [], [], 0
            end = time.time() + args.seconds
            interval = 1.0 / args.fps
            while time.time() < end:
                now = ev.ev("performance.now()")
                paths.append(shot(outdir, i))
                xs.append(now - t0)
                i += 1
                time.sleep(interval)
            return paths, xs, "realtime"

        gt = ev.ev(GT_JS % sel)  # exact ground truth before we disturb state (may be null pre-trigger)
        paths, xs, mode = capture("a")
        gt = ev.ev(GT_JS % sel) or gt
        bb = ev.ev(BBOX_JS % sel)
        if not bb:
            die("selector not found: " + args.selector)
        region = (max(0, int(bb["x"] * dpr)), max(0, int(bb["y"] * dpr)),
                  max(1, int(bb["w"] * dpr)), max(1, int(bb["h"] * dpr)))
        align = (mode == "realtime")  # poll-loop time is unreliable -> t0/D-invariant fit
        res = analyze_frames(paths, region, dpr=dpr, x=xs,
                             entering=args.entering, do_scale=args.scale, align=align)

        repro = None
        if not args.no_repro:
            paths2, xs2, mode2 = capture("b")
            res2 = analyze_frames(paths2, region, dpr=dpr, x=xs2, entering=args.entering,
                                  do_scale=args.scale, align=(mode2 == "realtime"))
            repro = _compare(res, res2)

        emit_json({"engine": engine, "device": device, "selector": args.selector,
                   "mode": mode, "dpr": dpr, "viewport": [vw, vh], "frames": len(paths),
                   "getAnimations": gt, "recovery": res, "reproducible": repro,
                   # consistent per-axis best-reading block (klass="time").
                   # Surfaces {easing, amplitude, rms, confidence} per axis;
                   # window is null (t0/D unknown in pixel recovery). Duration
                   # lives only in getAnimations above, not here. See
                   # motion_adapter.motion_summary for the contract.
                   "motion_summary": motion_summary({"recovery": res}, "time")})
    finally:
        ev.close()
    return 0


def _compare(a, b, amp_tol=0.05, name_must_match=True):
    """Reproducibility gated on the DOMINANT moving channel (largest |amp|).

    The weak channels (a barely-moving ty, the luminance opacity proxy) are
    noise and would flip a global AND to false for no reason. Report every
    channel's per-recapture match, but base the single `reproducible` verdict
    on the channel that actually carries the animation.
    """
    out = {"channels": {}, "dominant": None, "reproducible": None}
    dom, dom_amp = None, 0.0
    for ch in ("tx", "ty", "opacity", "scale"):
        ca, cb = a["channels"].get(ch), b["channels"].get(ch)
        if not ca or not cb or ca.get("easing") is None:
            continue
        amp_a, amp_b = ca.get("amp") or 0, cb.get("amp") or 0
        if abs(amp_a) < 1e-6:
            continue
        amp_ok = abs(amp_b - amp_a) / abs(amp_a) <= amp_tol
        name_ok = (ca.get("easing") == cb.get("easing")) or not name_must_match
        out["channels"][ch] = {"easing_a": ca.get("easing"), "easing_b": cb.get("easing"),
                               "amp_a": amp_a, "amp_b": amp_b, "ok": amp_ok and name_ok}
        if ch != "opacity" and abs(amp_a) > dom_amp:  # opacity is a proxy, not motion
            dom_amp, dom = abs(amp_a), ch
    out["dominant"] = dom
    out["reproducible"] = out["channels"][dom]["ok"] if dom else None
    return out


if __name__ == "__main__":
    raise SystemExit(main())
