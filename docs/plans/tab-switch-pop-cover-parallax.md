# Tab-switch pop → cover-parallax geometry

## Symptom
Router/tab-bar switches in the showcase app "jump around" — not seamless.

## Evidence (2026-08-10, iPhone 17 probe sim, iOS 26.5)
- Recorded `/tmp/tabs.mp4` (simctl) while cliclick-driving tab taps; per-frame
  gray diff profile shows the signature: smooth decaying deltas for ~10 frames
  (the 0.18-width slide) then a single-frame delta of 13–20 (vs ~2–8 during
  motion) — a hard cut. Key frames: outgoing tab still covers ~82% of the
  screen (tab bar already switched) until it vanishes in one frame.

## Root cause
`kit/ui_library/lib/widgets/arxa_kit_animated_tab_stack.dart`: with
`fade: false` (default, platform-view safety per flutter#24164/#148639) the
exit slot is painted ON TOP of the incoming layer, both fully opaque, and both
travel only `slideFraction` (0.18) of the width. When the controller completes,
`_exitingIndex = null` removes the still-82%-covering opaque exit layer in one
frame. Fractional paired slide is only self-consistent WITH a crossfade; with
fade off it guarantees a pop.

Contributing (not fixed here):
- First visit inflates a full tab shell mid-animation → dropped frames
  (visible as frozen-frame groups in the first-visit transitions).
- Rapid retarget mid-run snaps the interrupted exit by design.

## Fix (root cause, kit-level)
Cover-parallax geometry — same family as the app's Cupertino pushes, no
opacity, platform-view safe, removal of the exit layer is invisible because it
is fully covered when it happens:
- Incoming layer moves ON TOP and travels FULL width: begin
  `Offset(direction * 1.0, 0)` → `Offset.zero`.
- Exiting layer moves BELOW with parallax: `Offset.zero` →
  `Offset(-direction * slideFraction, 0)`.
- Stack order swap: exiting first (bottom), incoming second (top).
- `slideFraction` docs change meaning: parallax travel of the OUTGOING tab.
- `fade` stays opt-in with unchanged semantics (crossfade the pair).

## Touch list
- `kit/ui_library/lib/widgets/arxa_kit_animated_tab_stack.dart` — geometry,
  layer order, class docs.
- `kit/ui_library/test/kit/widgets/arxa_kit_animated_tab_stack_test.dart` —
  offset/order expectations.
- `kit/showcase_app/.../showcase_application_tab_host_widget.dart` — comment.

## Verify
- `flutter test` in kit/ui_library.
- Relaunch showcase on the sim, re-record, re-run the diff profile: no
  end-of-run spike an order of magnitude above the in-run deltas.
