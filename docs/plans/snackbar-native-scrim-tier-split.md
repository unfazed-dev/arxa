# Snackbar native scrim — tier split (ADR 0010 second amendment)

## Problem (root-caused, systematic-debugging phases 1–3)

Showcase app, default fidelity, iOS 26: tapping the split-send snackbar shows
the black54 dim but **no blur** — content beneath stays sharp. Frame-diff
measurement (f_012 vs f_020, `/tmp/snack_frames`): uniform −100..−136 luminance
(dim ✓) with zero high-frequency loss (blur ✗).

Chain:
1. GetX 4.7.3 mounts dim as the **child** of the `BackdropFilter` inside the
   same `overlayBlur > 0` entry (`snackbar_controller.dart:184-210`) — dim
   visible proves sigma 20 was mounted and active.
2. `arxaKitWithNativeChromeHidden` bumps `anyModalDepth`, but every in-page CN
   component defaults `autoHideOnModal: false` (vendor `modal_hide_mixin.dart`,
   deliberate post-Issue-#53 containment). Only the tab bar destroy-hides.
3. Mounted mid-page `UiKitView`s slice the scene; a Flutter `BackdropFilter`
   cannot sample lower CALayers → blur is a structural no-op on any
   platform-view-bearing page. The ADR 0010 amendment's premise ("the blur
   never has to cover a platform view") only holds for chrome-only pages.

## Fix (advisor-confirmed, option B)

Tier-split the scrim. On `ArxaKitPlatform.supportsLiquidGlass`:

- Kit-owned root-overlay entry inserted **before** the GetX entries:
  full-screen `LiquidGlassContainer` (`CNGlassEffect.regular`, `rect`) with the
  black54 dim as a Flutter layer **above** the glass (nothing readable from
  frame zero while the platform view attaches). Native UIKit glass blurs every
  layer beneath it — including other platform views.
- The scrim platform view is the scene-last platform view → per the engine
  view-slicer / plain-anchor mechanism, the later-painted Flutter snackbar ops
  hoist above it. (Same doctrine as the center pill's plain anchor; full-screen
  here is deliberate — a scrim *should* swallow taps: tap = dismiss.)
- GetX `overlayBlur` registered as `0.0` on this tier (no dead BackdropFilter,
  no double dim); other tiers keep sigma 20 + black54 unchanged.
- Lifecycle shares the existing wrapper: insert scrim, `present()`, await
  `SnackbarController.future` (completes after exit transition), fade scrim
  out, remove in `finally`. Chrome-hide counter unchanged (Issue 31 tab-bar
  exception untouched).

## Touch points

- `kit/ui_library/lib/utils/arxa_kit_native_overlay.dart` — scrim entry +
  extended wrapper param.
- `kit/ui_library/lib/services/notifications/arxa_kit_notification_service.dart`
  — pass overlay + tier flag.
- `kit/ui_library/lib/utils/kit_action/arxa_kit_snackbar_setup.dart` —
  tier-gated `scrimBlur`.
- `kit/ui_library/test/kit/utils/arxa_kit_native_overlay_test.dart` —
  insert/remove balance incl. throw path; scrim composition (glass below dim).
- `kit/core/NATIVE_COMPONENTS.md` — ADR 0010 second amendment note.

## Open (on-device verification required)

- Confirm snackbar Flutter ops hoist above the full-screen scrim view on
  device (slicer intersection). If they don't, fallback (C): opaque-heavy dim
  on native tier.
- Android/M3E tier has the same theoretical slicing limit with Compose views;
  out of scope here (different report, needs its own measurement).

## Status

- [x] Root cause pinned
- [x] Advisor consult (glm-5.3, anthropic wire, confidence 0.75 → option B)
- [ ] Implementation
- [ ] Tests green
- [ ] On-device video re-check
