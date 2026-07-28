#!/usr/bin/env python3
"""web_states — drive non-URL interaction state (G4) and capture what appears.

Navigate once, snapshot the REST skeleton, scan the page for interaction
affordances (aria-haspopup / aria-expanded / <details>/<summary>), click each,
re-snapshot WITHOUT re-navigating (so the triggered state survives), and diff to
record the nodes that appeared. Emits a content-free states.json:

  {"schema": "probe-states/1", "url": ..., "base_nodes": N,
   "states": [{"trigger": {"selector","kind","action"},
               "n_appeared": M, "appeared": [{"role","bbox","z"}, ...],
               "component": {"n_nodes": M, "nodes": [...]} | null,
               "transition": {"n_anims": K, "anims": [...]} | null}, ...]}

The per-state `component` (added by _states.build_component) is the revealed
subtree re-rooted as a content-free mini-skeleton (full fields + colors + mount),
null when nothing was revealed. See _states.build_component for the shape.

The per-state `transition` (added by _transition.build_transition) is the reveal
animation's content-free motion-law (which CSS properties animate + duration + delay
+ easing, bound to component nodes), read from the engine via getAnimations() in the
live window after the click. null when nothing animated. Coverage is best-effort (a
snapshot poll-race + JS-rAF blind spot are honest ceilings); each captured law's
value is exact. See _transition.build_transition for the shape.

Selectors are structural (tag:nth-of-type paths) — mechanism, not content. MUST
run on a CDP transport (host Chrome / --cdp-port); the ctx sandbox cannot reach
host Chrome."""
from __future__ import annotations
import argparse
import json
import time
from pathlib import Path

from _common import die, emit_json
from _web_eval import add_transport_args, navigate, resolve_web_eval
from web_skeleton import _snapshot_skeleton
from _states import classify_trigger, diff_skeletons, build_component
from _transition import build_transition
from _consent import detect_and_dismiss

# In-page scan: collect ONLY affordance candidates (targeted selector keeps the
# payload small) with a structural, content-free CSS path for each. Closed shadow
# roots and cross-origin frames are out of reach (documented hard limits).
_AFFORD_JS = r"""
(() => {
  const path = (el) => {
    const parts = [];
    while (el && el.nodeType === 1) {
      const tag = el.tagName.toLowerCase();
      let n = 1, sib = el;
      while ((sib = sib.previousElementSibling)) {
        if (sib.tagName === el.tagName) n++;
      }
      parts.unshift(tag + ':nth-of-type(' + n + ')');
      el = el.parentElement;
    }
    return parts.join(' > ');
  };
  const sel = '[aria-haspopup],[aria-expanded],summary,[role=menu]';
  const out = [];
  for (const el of document.querySelectorAll(sel)) {
    out.push({tag: el.tagName,
              role: el.getAttribute('role'),
              ariaHaspopup: el.getAttribute('aria-haspopup'),
              ariaExpanded: el.getAttribute('aria-expanded'),
              hasOpen: el.hasAttribute('open'),
              selector: path(el)});
  }
  return out;
})()
"""

_CLICK_JS = ("(() => { const el = document.querySelector(%s);"
             " if (!el) return false; el.click(); return true; })()")

# G6: content-blind occluding-overlay (consent-class) scan. Returns ONLY geometry +
# stacking + position for positioned, viewport-covering elements — never text/class/
# id. coverage = visible fraction of the viewport (rect clamped to the viewport).
# A broad pre-filter (fixed/sticky/absolute, coverage >= 0.3); _consent.classify_overlay
# is the policy gate that narrows to the occluding case (fixed + >=0.5 + z>0).
_OVERLAY_JS = r"""
(() => {
  const vw = innerWidth, vh = innerHeight, va = vw * vh;
  const out = [];
  for (const el of document.querySelectorAll('*')) {
    const cs = getComputedStyle(el);
    if (cs.position !== 'fixed' && cs.position !== 'sticky' && cs.position !== 'absolute') continue;
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    const x0 = Math.max(0, r.left), y0 = Math.max(0, r.top);
    const x1 = Math.min(vw, r.right), y1 = Math.min(vh, r.bottom);
    const w = Math.max(0, x1 - x0), h = Math.max(0, y1 - y0);
    const coverage = va > 0 ? (w * h) / va : 0;
    if (coverage < 0.3) continue;
    const z = parseInt(cs.zIndex, 10);
    out.push({position: cs.position,
              z: Number.isFinite(z) ? z : null,
              coverage: Math.round(coverage * 1000) / 1000,
              role: el.getAttribute('role'),
              bbox: {x: Math.round(r.left), y: Math.round(r.top),
                     w: Math.round(r.width), h: Math.round(r.height)}});
  }
  return out;
})()
"""

# G6 dismiss: the one content-blind, non-committal gesture. A synthetic Escape
# keydown/keyup on document. Never a button click (a blind click takes an unknown
# real action — accept-tracking / nav-away — violating the honest-ceiling principle).
_ESCAPE_JS = ("(() => { ['keydown','keyup'].forEach(t => document.dispatchEvent("
              "new KeyboardEvent(t, {key:'Escape', code:'Escape', keyCode:27, "
              "which:27, bubbles:true, cancelable:true}))); return true; })()")

# Capture the reveal animation in the LIVE window. CSS transitions/animations are
# created on the next style recalc, so reading getAnimations() in the same microtask
# as the click returns empty; wait ~1-2 frames (NOT the full settle, which would let
# a short reveal finish), THEN read. Pinned by fixtures/transition/spike_getanimations.py.
_LIVE_WINDOW = 0.05

# In-page DECLARED-law reader: per running animation, its timing (duration/delay/
# easing/iterations), per-keyframe easings, the animated CSS property NAMES (never
# values), and a bbox anchor. Content-free: numbers + easing strings + property names
# + geometry. iterations non-finite -> null (ambient loop, dropped downstream).
_TRANSITION_JS = r"""
(() => document.getAnimations().map(a => {
  const e = a.effect; if (!e || !e.getTiming) return null;
  const t = e.getTiming();
  const kfs = (e.getKeyframes && e.getKeyframes()) || [];
  const tgt = e.target;
  const r = (tgt && tgt.getBoundingClientRect) ? tgt.getBoundingClientRect() : null;
  return {
    duration: (typeof t.duration === 'number') ? t.duration : null,
    delay: t.delay || 0,
    easing: t.easing || null,
    iterations: Number.isFinite(t.iterations) ? t.iterations : null,
    kfEasings: kfs.map(k => k.easing).filter(Boolean),
    props: [...new Set(kfs.flatMap(k => Object.keys(k).filter(
             p => !['offset','easing','composite','computedOffset'].includes(p))))],
    bbox: r ? {x: Math.round(r.left), y: Math.round(r.top),
               w: Math.round(r.width), h: Math.round(r.height)} : null
  };
}).filter(Boolean))()
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=None, help="write states.json here")
    p.add_argument("--max", type=int, default=8,
                   help="cap the number of triggers driven (default 8)")
    add_transport_args(p)  # supplies --url + transport/device flags
    args = p.parse_args()
    if not args.url:
        die("web_states needs --url (the page to drive interaction state on).")

    engine, ev, device = resolve_web_eval(args)
    try:
        if not hasattr(ev, "sess"):
            die("web_states needs a CDP transport (chrome host / --cdp-port).")
        navigate(ev, engine, args.url)
        rest, _, _, _ = _snapshot_skeleton(ev, args.url)
        base_nodes = len(rest["nodes"])

        # G6: record the load-time occluding overlay (consent-class) as a State and
        # attempt one content-blind Escape dismiss. None when no overlay is detected
        # (the common case — §C7: overlays cover the DOM, they don't remove it).
        consent = detect_and_dismiss(lambda: ev.ev(_OVERLAY_JS),
                                     lambda: ev.ev(_ESCAPE_JS), time.sleep)

        cands = ev.ev(_AFFORD_JS) or []
        triggers = []
        for c in cands:
            t = classify_trigger(c)
            if t:
                triggers.append({"selector": c["selector"], **t})
        n_found = len(triggers)

        states = []
        for tr in triggers[:args.max]:
            # Per-trigger try/except: a transient snapshot/CDP error skips THIS
            # trigger rather than aborting the sweep (states already collected are
            # still emitted). ev.ev() signals in-page JS errors via die()->SystemExit,
            # which is intentionally NOT caught — a malformed selector is a real bug.
            try:
                pre, _, _, _ = _snapshot_skeleton(ev, args.url)  # fresh baseline: no cross-attribution
                opened = ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                if not opened:
                    continue
                time.sleep(_LIVE_WINDOW)               # ~1-2 frames: reveal now running
                trans_raw = ev.ev(_TRANSITION_JS) or []  # read declared law WHILE animating
                time.sleep(0.3)                        # let the reveal finish laying out
                after, _, _, _ = _snapshot_skeleton(ev, args.url)
                d = diff_skeletons(pre, after)
                comp = build_component(pre, after)
                trans = build_transition(trans_raw, comp) if comp else None
                states.append({"trigger": tr, "n_appeared": d["n_appeared"],
                               "appeared": d["appeared"], "component": comp,
                               "transition": trans})
                # best-effort toggle-back (re-baselining makes correctness not depend on it)
                ev.ev(_CLICK_JS % json.dumps(tr["selector"]))
                time.sleep(0.15)
            except Exception:
                continue

        out_obj = {"schema": "probe-states/1", "url": args.url,
                   "base_nodes": base_nodes, "consent": consent,
                   "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                   "states": states}
        if args.out:
            Path(args.out).write_text(json.dumps(out_obj, indent=2))
            emit_json({"ok": True, "out": args.out, "consent": consent,
                       "triggers_found": n_found, "triggers_driven": min(n_found, args.max),
                       "states": len(states),
                       "components_built": sum(1 for s in states if s["component"]),
                       "transitions_built": sum(1 for s in states if s.get("transition")),
                       "appeared_total": sum(s["n_appeared"] for s in states)})
        else:
            emit_json(out_obj)
    finally:
        ev.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
