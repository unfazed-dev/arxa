# HANDOFF — capture-gap fixes (probe-runner)

> Continue here. cwd = this repo (`~/Developer/artificial_intelligence/skills/probe-runner`).
> Prior work ran from `nebula`; all probe-runner artifacts now live HERE. nebula is done.

## Where things stand (2026-05-30)

**Goal:** reproduce any site/app from a URL — pixel + tokens + animation, minus IP.
Reproduction target = **tiered-honest** (user-chosen): DOM-substrate tier → full repro after
fixable gaps; canvas/WebGL/video/cross-origin tier → behavior-box + owned-only clip IS the
faithful output (literal 3rd-party pixels are IP-blocked).

**Research complete.** Ran full pipeline on 7 varied awwwards sites + 8-site arch-scan +
5 reference probes + 4 baselines (24 total). Arch axis is CLOSED (4 axes mapped).
**Headline: 0/7 clean ✓✓✓; AIR is the near-miss (blocked only by G4).** Hard blockers =
canvas/WebGL substrate (5/7 incl video) + GSAP-scroll motion (3/7). Acquisition is FINE for
awwwards (G1/G6 don't bite). Firewall + DOM pipeline sound.

### Repo state
- Clean working tree, `master` synced to `origin/master` (`946f92d`). No stray branches/worktrees.
- This is the SOLE maintained probe-runner copy (GitHub `unfazed-dev/probe-runner`). Downstream copies FROZEN.

## Read these first (in this repo)
1. `docs/plans/probe-runner-engine-capture-gaps.md` — **master findings** (~33KB).
   §A taxonomy+backlog · §C awwwards sweep · §C6 arch-completeness · §C7 same-pipeline isolation ·
   §C9 **corrected synthesis + authoritative fix priority**.
2. `research/capture-gap-probes/README.md` — harness + full 24-site manifest + how-to-run.
3. `docs/plans/probe-runner-total-capture-tdd-plan.md` — prior TDD plan (mode design).

## Gap catalog (legend)
G1 hydration-settle (slow-SPA only, NOT awwwards) · G2 virtualization · G3 multi-route ·
G4 non-URL state · **G5 canvas/WebGL substrate (dominant)** · G6 consent (does NOT block —
overlays cover, don't remove) · **G7 GSAP scroll-motion invisible to WAAPI** ·
G8 scroll-driven-motion model · G9 video-bg · **G10 web_tokens shadow-DOM blindness** ·
G11 cross-origin iframe opaque.

## Authoritative fix priority (§C9)
- **P0 — G7/G8 scroll-driven motion.** Flipbook currently driven by TIME; scroll-motion is driven
  by scroll POSITION. Fix = capture scroll→progress curves (scrub timeline), not wall-clock frames.
  Unblocks the most DOM-tier sites (ashley 80 ScrollTriggers, razorpay, detroit). **START HERE.**
- **P1 — G10 shadow-DOM walk** (web_tokens pierces shadow roots) **+ G4 non-URL state triggers.**
- **P2 — G5/G9/G11 substrate-honesty** (behavior-box + owned-clip emission for canvas/WebGL/video/x-origin).
- **P3 — G1 settle** (RSC-safe: max-wait + network-idle) **+ G6 dismiss.**

## Next step — DONE (2026-05-30): P0 plan written + diagnosis CORRECTED
**Plan:** `docs/plans/p0-scroll-driven-motion-fix.md` (ready to execute, task-by-task).

**Diagnosis corrected by direct measurement (the old G7/G8 framing was WRONG):**
- `web_anim` is **already scroll-position-driven**; it never calls `getAnimations` (grep: only in
  `research/`). The "getAnimations=0 ⇒ blind" claim came from the canary `aw_probe.py`, which ran
  **no** `web_anim`. The flipbook framing is dead.
- Live Ashley (host CDP): range [0,12550], **60 movers** discovered. Real gaps:
  (1) **readiness-wait** — web_anim measured a pre-hydration shell → `range 0:0` → died (this hid all
  motion); (2) **multi-segment** timelines — 41/60 channels; (3) **band-localized** sampling — 21/60;
  (4) `--top 12` vs 60+. **Virtual-scroll NOT the gap** (Ashley/Razorpay native) → deferred.
- Deterministic fixtures + asserting harness on disk: `fixtures/scroll-motion/` (native-scrub GREEN,
  multiseg/band AMBER, late-build/virtual RED) + `run_anim.py`. §A G7/§C3.2/§C9 marked SUPERSEDED.
- **Uncommitted.** To resume: execute `p0-scroll-driven-motion-fix.md` (subagent-driven or inline).

## Standing constraints (carry forward)
- **CAVEMAN MODE full** (terse; code/commits/security normal).
- **context-mode routing:** curl/wget/WebFetch BLOCKED → ctx tools. Bash short-output only.
- **CDP harness MUST run on host Bash** (ctx sandbox can't reach host `localhost:9334`),
  often needs `dangerouslyDisableSandbox:true`. macOS has no `timeout` (self-bound wait loops).
- **Verify via exit codes / byte-sizes / git** — device fabricates tool-result text.
- **Git commits single-line, NO author/Co-Authored-By trailer. Stage files EXPLICITLY** (never `git add -A/.`).
- **Plans/docs → `docs/plans/<kebab-title>.md`.**
- **IP firewall:** never persist copyrighted content — counts/ratios/class-labels only.
- **Login pages:** capture public structure only, no credential entry.
- **Call advisor** before substantive work + before declaring done.
