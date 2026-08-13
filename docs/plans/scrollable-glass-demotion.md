# Scrollable glass demotion — enforce the tier split automatically

> ⚠️ SUPERSEDED by ruling 4 (2026-08-13, `docs/liquid-glass-allowlist.md` §2):
> the in-scroll auto-demotion this plan designed was removed kit-wide once the
> liquid-glass law gated away the compositions that caused the artifacts. Kept
> as the evidence trail for the demotion era; the glass card / toolbar half of
> this plan never landed beyond an uncommitted working tree. See
> `docs/plans/showcase-law-application.md` §S4.

## Problem (evidence: two device recordings, 2026-08-12)

Glass `CNButton` platform views inside scrollables lose their glass material
while their labels keep painting:

- **Notes auth view** (`showcase_notes_auth_view.mobile.dart:167-194`): three
  `AppBoxKitNativeButton(style: glass)` pills in a `SingleChildScrollView` lose
  glass near the bottom tab bar on scroll return. No app-side hider is in the
  wrapper chain (verified — no edge effect, no gate, no occlusion). Standing
  suspects: the never-unwrapped `.wake()` `SlideTransition`
  (`appbox_kit_wake.dart:88-96`), the unconditional `ClipRect`
  (`vendor .../button.dart:694`), and glass-sampling-glass under the tab bar.
- **Profile shell** (`showcase_profile_view.mobile.dart:62`): the edge-aware
  list's uniform `Opacity` fade (`appbox_kit_scroll_edge_effect.dart:211,228`)
  computes fade fraction over the **whole card's** height (`:172-174`), so a
  pill near a card's top dims while still ~88px clear of the tab bar; glass
  reads as gone at ~0.77 alpha while text stays readable.

The kit already outlaws the pattern: `appbox_kit_scroll_edge_effect.dart:62-68`
— "Platform-view glass does not belong inside a scrollable at all under the
tier split." Apple (WWDC25 sessions 284/356) and Flutter (issues #103014,
#107486, #86787, #78205) both put glass in persistent chrome only.

## Decision (user-approved)

Enforce the tier split mechanically: any `AppBoxKitNativeButton` that finds
itself inside a scrollable auto-demotes to the vendor's existing Flutter
Cupertino fallback tier (`_buildCupertinoFallback`, the same path iOS < 26
uses). No call-site changes; chrome outside scrollables keeps real glass.

"There is no scroll-down solution": scroll-down merely moves buttons away from
the trigger zone. The tab-switch alpha-hide (`00bc2f0c`) is unrelated and
correct — do not touch.

## Implementation

1. Vendor local patch (`cupertino_native_better/lib/components/button.dart`):
   `CNButtonConfig.preferFlutterTier` (default false); `build()` treats it as
   `shouldUseNative &&= !preferFlutterTier`.
2. Kit (`appbox_kit_native_button.dart`): pass
   `preferFlutterTier: Scrollable.maybeOf(context) != null`.

## Verification

- `flutter analyze` clean on ui_library + showcase_app.
- Re-record auth + profile scroll on device: pills must keep their surface in
  both directions (they are now Flutter-drawn, faded coherently by the edge
  effect).

## Round 2 (2026-08-12, third recording): full enforcement

Button-only demotion produced a half-applied rule: demoted CTAs sat next to
still-native sliders/switches/segmented/split-button/glass-cards, and the auth
"Sign In" fallback rendered label-invisible (vendor fallback used a plain-style
`CupertinoButton` whose default foreground == primaryColor == the fill; fixed
by LOCAL PATCH #5 passing `foregroundColor`, test-covered).

Audit results (full inventory in agent report):
- **Lag floor: 17 live platform views** composite every frame once all tabs are
  visited (tab stack holds visited shells at 1/255 alpha): Home 5 + Search 6 +
  Profile 6; Motion route adds 8, note editor adds an IconButton **per photo**.
  Flutter docs: platform views are "expensive… avoid when a Flutter equivalent
  is possible".
- **Apple's per-control rule (WWDC25 219/284/356, forums thread 791070):**
  glass layer = tab bars, nav bars/toolbars, sidebars, sheets, popovers, menus,
  FABs, docked search chrome. Content layer = switches, sliders, segmented
  controls, text fields, in-form CTAs, progress — standard controls that only
  lift into glass transiently during touch. Glass inside a scroll view is an
  explicit anti-pattern, as is glass-on-glass.

Enforcement: thread `preferFlutterTier` (LOCAL PATCH #6) through slider,
range_slider, switch, segmented_control, search_bar, text_field, split_button,
glass_button_group, popup_menu_button, glass card container; every kit wrapper
auto-detects `Scrollable.maybeOf`. One chrome exception: the pinned notes
folder search bar (inside a CustomScrollView but pinned) gets `chrome: true`.

## Round 3 (2026-08-12, same day): partial reversal — allowlist supersedes

Round 2 over-generalized. Apple's "no glass in scroll views" rule targets glass
SURFACES (platters/cards/containers), never interactive controls — Apple never
swaps a control for a non-glass variant in scroll content, and the segmented
control's indicator is glass even at rest inside lists. Blanket control
demotion was reverted the same day it shipped.

Superseding authority: **docs/liquid-glass-allowlist.md** (grilled decisions:
Apple-fidelity governs; controls native everywhere; buttons native everywhere
with in-scroll style mapping glass→tinted / prominentGlass→filled; glass
surfaces stay demoted in scrollables; lag = land-then-measure, keep-alive
untouched without device evidence). This plan doc is historical context; the
allowlist is the living rule.

## Follow-ups (not in this change)

- Edge-effect whole-card fade denominator: re-judge after demotion; at 0.77
  alpha Flutter pixels barely register, so the defect may be immaterial once
  glass is out of scroll content. If still visible, fade per-leaf or scrim the
  chrome instead of fading content (Apple's scroll-edge model).
- Other `CN*` platform views inside scrollables (switches, sliders, fields in
  forms) — audit under the same rule if artifacts appear.
- Auth root cause (wake transform vs ClipRect vs glass-over-glass) left
  unpinned; demotion removes the exposure without the device probe.
