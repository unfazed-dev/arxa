# Scroll-animation instrumentation (`web_anim.py`)

## Goal
Give probe-runner a command that characterizes scroll-driven animations with
**certified determinism** — every easing it emits is either measured at proven-
deterministic scroll positions or withheld. No eyeballing, no guessing. This is
the generalization of the manual DOM instrumentation that took the
kasane-keyboard hero pan from "medium confidence" to 100%.

## Why static scroll sampling = 100%
Modern sites (Lenis/GSAP-scrub/CSS scroll-driven) bind a CSS property to scroll
position: `prop = f(scrollY)`. If you sample during a live/animated scroll you
measure `f(lenisSmoothedScroll)` with inertial lag + frame-drop jank — garbage.
If you instead **set scrollY statically, let the smooth-scroll lib settle, then
read the computed style**, you recover `f(scrollY)` exactly. Determinism is
*provable*: `window.scrollY` must equal the target (within tol) and the property
must be stable over time at fixed scroll. Both held on kasane (actualY===targetY
at every point) — that proof is the product.

## Contract (the "always 100%" guarantee)
- Emits an easing fit ONLY for channels where: `max|actualY-targetY| <= tol`
  AND the channel is stable at fixed scroll (scroll-scrubbed, not time-based).
- Channels failing either check → `certified: false`, reason given, NO fit.
- Time-based / scroll-triggered tweens are flagged, not fitted → use `web_record`
  for temporal capture instead. (getAnimations/WAAPI dump = future `--mode css`.)

## Method (Python-driven, short CDP calls)
1. **detect** — eval for Lenis / GSAP+ScrollTrigger / Locomotive / Framer /
   React / scroll-behavior. Reports the animation regime.
2. **discover** (skip if `--selector`) — snapshot decomposed transform
   `[tx,ty,sx,sy,rot,opacity]` of every `body *` at ~4 scroll positions
   (lo/⅓/⅔/hi), accumulate per-element max delta IN-PAGE (tiny payloads), pick
   top-K movers, tag with `data-pa=<rank>`. Catches transforms, scale, fades.
3. **measure** — sweep scrollY across N static steps; at each: set scroll
   (scroll-behavior:auto), sleep `settle`, read every tagged mover's channels +
   actual scrollY. One short eval per step → no long-blocking recv.
4. **certify** — global drift gate + per-(mover,channel) stability probe
   (read twice at a mid step, Δ must be ~0).
5. **fit** — per varying+certified channel: find active sub-range (start→lock),
   normalize, fit against a 20-entry standard easing library
   (linear/ease/in/out/inOut × quad/cubic/quart/expo/sine), report best + RMS;
   `custom` if RMS > 0.1.
6. **cleanup** — remove `data-pa` attrs + `delete window.__pa` in a finally.

## Output
`out_path("anim","json")`: url, stack, scrollRange, steps/settle, global
certified + maxDriftPx, and per mover {sel,txt, channels:{tx:{from,to,
activeRange,easing:{name,bezier,rms},certified}}, dominant, series}. Concise
human summary to stdout; emit the JSON path last.

## Self-test (verification, not smoke test)
Re-run on the kasane hero. MUST reproduce: "Handcrafted" tx −89→−720, lock
≈scrollY 1320, best easing `ease-out` cubic-bezier(0,0,0.58,1) RMS ≤ 0.05,
mirror line "With Urushi" +89→+720. If not reproduced, the tool is wrong — fix
before shipping.

## Propagation
Build + verify in the working copy
(`artificial_intelligence/skills/probe-runner`), then — on user confirmation —
copy into the tracked skill copies (`engineering-pack`, `brainiac`
`.claude/skills/probe-runner/scripts/`) and commit. Pushing is outward-facing →
confirm first.

## Scope (v1)
`--mode scroll` only. `--mode css` (getAnimations dump) and screenshot
cross-check deferred unless requested.
