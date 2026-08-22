# Entrance animation — research findings (2026-08-22)

Question: the right timing and technique for the gen_ui surface entrance — the
staggered reveal in arxa-studio `plugins/gen-ui/lib/client.js`. The operator
asked how tools like FlutterFlow do it; this is the answer, with the numbers
that shipped.

## Duration

- Material 3 duration tokens (AOSP `MotionTokens.kt`, androidx-main): Short
  50/100/150/200, Medium 250/300/350/400, Long 450–600, ExtraLong 700–1000.
  Small components entering the screen belong to the short-to-medium band.
  **Shipped: 250ms (DurationMedium1).**
- Entrances over ~500ms read as slow; under ~100ms they read as a glitch —
  which is why the reveal never animates a surface faster than its stagger
  step and why the pending glow only earns its wait (PENDING_AFTER_MS 400).

## Easing

- Elements ENTERING the screen decelerate; accelerate curves are for exits.
  M3 emphasized-decelerate = `cubic-bezier(0.05, 0.7, 0.1, 1)`
  (`EasingEmphasizedDecelerateCubicBezier` in the same source). Standard =
  (0.2, 0, 0, 1); legacy decelerate = (0, 0, 0.2, 1).
  **Shipped: emphasized-decelerate, pinned by selftest.**

## Stagger

- Practitioner consensus is 50–100ms between siblings (no single primary
  source owns the number; FlutterFlow exposes the same idea as a per-widget
  **Delay** property, and Material choreographs menu items with small
  sequential offsets).
- The cap matters more than the step: excessive motion measurably raises
  perceived delay (see streaming-generative-ui-research.md §6), so a large
  surface must finish near 0.7s regardless of item count.
  **Shipped: 90ms step, 720ms whole-surface cap — unchanged, now sourced.**

## Technique

- Animate **transform + opacity only**: both run on the compositor and cannot
  trigger layout. Never animate height/width/margin — the Slot has already
  reserved the real height, so nothing needs to move but the pixels.
- Rise distance: the FlutterFlow Slide spans ±100px+ because it animates
  full-screen entries; for item-level entrances the consensus is a small
  4–16px rise. Larger reads as a notification arriving, not a surface
  assembling. **Shipped: translateY(8px), fill-mode `both`.**
- `prefers-reduced-motion`: BOTH layers must stand down — the CSS animation
  via the media query AND the JS stagger clock (timed swaps are motion too).
  A media query alone leaves reduced-motion users watching a surface assemble
  in slices. **Shipped: media query in ENTER_CSS + clock stand-down in
  useReveal, each pinned by its own selftest.**
- Interruptibility: if more content arrives mid-entrance (two-phase fill,
  streaming §8), a 250ms transform/opacity animation is safe to interrupt —
  the browser composes from the current frame; no FLIP bookkeeping is needed
  at this scale. Do not add one.

## What FlutterFlow actually ships (the comparison asked for)

Widget-level animations: **Fade** (opacity 0→1), **Slide** (position offset
in px), **Scale**, **Rotate**, each with a **Duration** and **Delay** and
start/end values. The standard entrance pairing is Fade+Slide with a small
delay — the same pair shipped here, with the M3 entering curve behind it.

## Generative / streaming UI state of the art

- The CopilotKit OpenGenerativeUI issue #33 (progressive rendering for
  generative components) shows the industry still has no settled
  streamed-reveal pattern beyond skeleton-to-content. v0/Builder/Relume
  emit complete surfaces.
- The honest framing stays the one in streaming-generative-ui-research.md:
  ours is an ENTRANCE animation over complete args, not streaming, until the
  §7 provider measurement (zai/glm-5.3 tool-call-chunks) says otherwise.

## Sources

- [MotionTokens.kt — AOSP androidx-main](https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/MotionTokens.kt) — duration tokens, emphasized-decelerate curve
- [FlutterFlow — Widget Animations](https://docs.flutterflow.io/concepts/animations/widget-animations/) — Fade/Slide/Scale/Rotate + Duration/Delay surface
- [CopilotKit/OpenGenerativeUI #33](https://github.com/CopilotKit/OpenGenerativeUI/issues/33) — progressive rendering for generative UI
- [streaming-generative-ui-research.md](./streaming-generative-ui-research.md) §6 — skeleton/motion rules this repo already ratified
