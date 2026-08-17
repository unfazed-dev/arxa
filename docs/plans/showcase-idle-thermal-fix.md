# Showcase app idle-warmth diagnosis + fix (2026-08-27)

## Symptom

Showcase app (`kit/showcase_app`) on a physical iPhone (iOS 26), launched with
`flutter run` (debug mode), warms the device within a few minutes **while
sitting idle on the launch (home) screen**. Confirmed via operator grill:
debug run mode, iPhone iOS 26, idle-on-launch-screen, scope = diagnose + fix.

## Root-cause chain (ranked)

1. **Perpetual indeterminate spinners on the idle home surface** — the
   mechanism. `showcase_progress_loading_card_widget.dart` mounted
   `AppBoxKitNativeProgress.circular()` + `AppBoxKitNativeLoadingIndicator`
   (both → Flutter `CupertinoActivityIndicator` on iOS) with **no bound**.
   The home list is a non-lazy `ListView(children:)`
   (`appbox_kit_edge_aware_list_view.dart:149`), so both spinners tick from
   launch, forever, at the display rate.
2. **120 Hz** — `CADisableMinimumFrameDurationOnPhone=true`
   (`ios/Runner/Info.plist:5`) doubles the tick rate (120 frames/s of
   scheduled work instead of 60).
3. **Hybrid-composition scene multiplier** — the iOS 26 home surface carries
   native chrome as UiKitViews (native tab bar, glass cards via
   `LiquidGlassContainer`, FAB menu). Every scheduled frame recomposites the
   whole scene with platform-view slicing, so a 32px spinner forces
   full-scene composites at 120 Hz.
4. **Debug-mode confound** — `flutter run` default: JIT Dart + asserts.
   Multiplies per-frame cost; thermal conclusions must be drawn from
   `--profile`/`--release` runs (docs.flutter.dev/testing/build-modes).

## What was ruled out (with evidence)

- Unbounded Dart animations in app/kit code: none at idle — the only
  `..repeat()` is the typing indicator, mounted 1.6 s per send
  (`showcase_components_conversation_widget.dart:156`).
- Flutter-side blur stacking: 0 simultaneous `BackdropFilter`s on the iOS 26
  launch surface; glass defaults are opaque (`opaqueGlass`/`platformViewSafe`
  drop the blur saveLayer). Worst Flutter blur sites are transient/opt-out only.
- Location/sensors/sockets/polling: none in the app.
- Timers: only the user-triggered 1 Hz voice-bubble timer (pushed route).

## Fix applied (behavior-TDD: red → green)

`showcase_progress_loading_card_widget.dart` — the indeterminate demos now
spin for a 5 s demo window on appearance, then freeze under
`TickerMode(enabled: false)`; a `Replay` button (`AppBoxKitNativeButton`,
plain style) restarts the window. Determinate bar unchanged (static).
Tests: `test/showcase_progress_loading_idle_test.dart` — iOS 26 glass tier
auto-stop + fallback-tier replay, both citing `[Progress demo]`.

## Why this matches official best practice

- Flutter API docs: `BackdropFilter` "is relatively expensive, especially if
  the filter is non-local, such as a blur" — clip tightly, prefer
  `ImageFiltered`, group multiple blurs (`BackdropGroup`/`.grouped`).
  (api.flutter.dev/flutter/widgets/BackdropFilter-class.html)
- Flutter perf docs: every frame under 16 ms "improves battery life and
  thermal issues"; avoid `saveLayer` triggers (`Opacity`, `ShaderMask`).
  (docs.flutter.dev/perf/rendering/best-practices)
- Apple HIG Materials: Liquid Glass is the **navigation/controls layer only** —
  "Don't use Liquid Glass in the content layer", "Use Liquid Glass effects
  sparingly… limit to the most important functional elements."
  (developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.md)
- Apple spinners are *transient* by design (visible while work is happening).
  A spinner that never stops is perpetual render work — nothing may animate
  on a surface that should idle.

## Third pass (2026-08-27): in-scroll glass jitter/flicker

Symptom: native liquid glass jitters/flickers while scrolling. Root cause
(systematic-debugging, evidence: `LiquidGlassContainerView.swift`,
`appbox_kit_edge_aware_list_view.dart:110-122`, M5 harness): in-scroll glass
cards are UiKitViews the engine detaches/re-adds at the paint-cull boundary
— the top edge has overdraw headroom, the trailing edge does not — and every
live glass view is composited per scroll frame. The law's own remedy applied:
deselect ladder step 1 (docs/liquid-glass-allowlist.md, ruling 4) —
`AppBoxKitGlassCard` demotes to the frosted tier inside Scrollables
(`Scrollable.maybeOf(context) != null`); opaque fill under `opaqueGlass` =
zero blur, zero platform views in the scroll. Chrome/controls stay native.
Tests: `appbox_kit_glass_card_test.dart` (in-scroll frosted / out-of-scroll
native), M5 vacuity control re-scoped to CN controls. Pending: device
confirmation; next ladder rung = toolbar if artifacts persist.

## Remaining recommendations (not applied — deliberate architecture calls)

- **Verify on device in profile mode**: `flutter run --profile`; warmth
  claims from debug runs are unmeasurable-by-confound.
- **TickerMode for the hub's keep-alive stacks**: the `StackedTabsRouter`
  IndexedStack (`app.dart:30`) never mutes covered tabs' tickers — latent;
  the in-view `AppBoxKitAnimatedTabStack` muting was APPLIED in the
  gap-closure pass and home's spinner demo is bounded to a 5s window, so no
  perpetual animator lives covered today.
- **`RepaintBoundary` coverage still thin** (one landed on the conversation
  typing bubble in the gap-closure pass): latent; matters when a perpetual
  animator next lands next to expensive paint.
- **Out-of-scroll content-layer native glass on iOS 26** (GlassCard →
  `LiquidGlassContainer` per card on static surfaces — in-scroll cards already
  demote, ladder step 1) is the remaining frame-cost multiplier; HIG
  "sparingly" supports routing those cards to the frosted tier
  (`wantNative: false`) if thermals still matter after this fix. ADR 0010 owns
  that call.
- `enableGPUValidationMode = "1"` in Runner.xcscheme — STRIPPED in the
  gap-closure pass; do not re-enable it for perf runs.

## Whole-app sweep (follow-up: other shells + pushed routes)

Every perpetual-work class swept across `kit/showcase_app/lib` +
`kit/ui_library/lib` + `kit/motion/lib`:

- **Framework-internal indicators** (the class that bit us on Home):
  one other hit app-wide — `showcase_startup_loading_widget.dart:54`
  (`CircularProgressIndicator`), bounded by design: the startup route shows
  for the 2s min-display then `replaceWith` disposes it.
- **flutter_animate loops / shimmer / skeleton / marquee**: none (one
  `.animate(adapter:)` on the pushed Motion route, bounded; zero
  shimmer/skeleton widgets in the kit).
- **Dart controllers / timers / streams** (full inventory, subagent sweep):
  only the typing indicator (1.6s windows on a pushed route) and the
  user-triggered 1Hz voice-bubble timer.
- **Maps** (`ShowcaseMapsView`): pushed route under the profile shell,
  user-driven; a static map schedules no frames.
- **Tab roots (home/search/profile/notes)**: no perpetual animator in any
  root today. Notes mounts eagerly (keep-alive) but only subscribes a stream.

### Gap closure (2026-08-27, second pass — all addressed)

- **Tab ticker muting — FIXED.** `appbox_kit_animated_tab_stack.dart`: every
  hidden tab is now wrapped in `TickerMode(enabled: i == _currentIndex)` in
  BOTH hiding modes (Offstage and iOS alpha/translate); the exit slot stays
  unwrapped so the leaving tab ticks through its exit, then mutes on
  completion. Red-first tests in
  `kit/ui_library/test/appbox_kit_animated_tab_stack_test.dart`
  (`kit.ui_library.animated-tab-stack` — iOS cross-cut + animated tier).
  The alpha/translate platform-view containment idiom is untouched.
- **Typing indicator — HARDENED.**
  `showcase_components_conversation_widget.dart`: the pulsing dots now sit
  under a `RepaintBoundary` (per-frame invalidation confined to the bubble)
  with the static label hoisted into `AnimatedBuilder.child`. Behavior
  identical; the only remaining `repeat()` in the app now repaints in
  isolation.
- **xcscheme — STRIPPED.** `enableGPUValidationMode` removed from
  Runner.xcscheme (Xcode-attached runs no longer pay Metal validation).
- **Addressed by decision note, not code** (design decisions, not defects):
  snackbar scrim σ20 (`appbox_kit_snackbar_setup.dart:50`, transient,
  non-iOS-26 tiers), sheet σ30 opt-out (`appbox_kit_native_sheet.dart:381`,
  zero callers), scroll-edge animated sigma (tier-gated, identity at rest),
  and the iOS 26 GlassCard→native-glass default (ADR 0010 owns the tier
  split; flip only if a post-fix profile-mode device run still shows
  warmth).

### Latent guards — status after second pass

- ~~Hidden tabs not ticker-muted~~ → **FIXED** (see gap closure above).
- `RepaintBoundary` coverage: the one per-frame painter (typing bubble) is
  now bounded; the rest of the app has no per-frame painters to isolate, so
  blanket boundaries remain unnecessary (YAGNI). Add one alongside any
  FUTURE perpetual animator as a matter of course.

### Latent blur exposures (glass audit — none active on the launch surface today)

- `appbox_kit_scroll_edge_effect.dart:211,300` — the only *animated* sigma,
  driven per scroll frame, wrapped 2× per list child app-wide. Mitigated
  (tier-gated off on iOS 26, identity layer at rest, 1/50 quantization) but
  the first place to look if long frosted-tier lists ever run hot.
- `appbox_kit_snackbar_setup.dart:50` — full-screen σ20 BackdropFilter scrim
  for a snackbar's whole lifetime on non-iOS-26 tiers.
- `appbox_kit_native_sheet.dart:381` — full-screen σ30 blur if any caller
  passes `opaqueGlass: false` (none do today); keep callers opaque.

## Fourth pass — whole-app leftover sweep (2026-08-27, four parallel audits)

Four report-only audits fanned out over the app + kit: native views in
scrolls, perpetual work, compositing/blur/list health, and fix
leftovers/consistency. Combined verdict: **0 BLOCKER, 4 GAP (3 code, 1
law-pending), 33 NOTE**.

### Fixed this pass (behavior-TDD, red-first)

- **Full-res photo decodes in the strip** —
  `showcase_note_photo_strip_widget.dart` rendered 84×84pt thumbs from the
  full capture (up to 2048px) with no decode bound. Now
  `cacheWidth/cacheHeight = 84pt × devicePixelRatio` (→ `ResizeImage`). Pin:
  `showcase_note_photo_strip_widget_test.dart` (`[Photo display] — …
  thumbnails decode at display pixels`).
- **I/O in the scroll-item build path** — the strip's `FutureBuilder`
  re-created `resolvePath(attachment)` per rebuild, re-running
  `getApplicationDocumentsDirectory` + `Directory.create` through the
  facade/adapter chain every time. `ShowcaseNoteEditorViewModel.resolvePath`
  now memoizes per attachment id (`_resolvedPathFutures`, cleared on
  dispose). Pin: `showcase_note_editor_viewmodel_test.dart`
  (`notes.attach-a-photo-to-a-note — resolvePath memoizes per attachment id`).
- **Drawer glassPeek blurred over the UiKitView scene** —
  `appbox_kit_drawer.dart`'s default variant used the σ20 frosted branch over
  a host page that hosts native glass on iOS 26 (BackdropFilter cannot sample
  platform views, flutter#175048). Now tier-gated: `platformViewSafe` +
  opaque tint on `supportsLiquidGlass` (sheet/dialog recipe); the blur stays
  below the tier where it IS the material. Pins:
  `appbox_kit_drawer_test.dart` (both directions).

### Law-pending (deliberately NOT fixed)

- **In-scroll native toolbar** (`showcase_profile_toolbar_demo_widget.dart:27`
  in the profile EdgeAwareListView) — deselect-ladder rung 2; fires only if
  the device run still shows artifacts (attribution first, never blanket).

### Unverified residuals (device run decides)

- `AppBoxKitGlassWarmup` keeps one offscreen `LiquidGlassContainer` + a
  `CNSwitch` translated 100000px off-screen for the app's lifetime (deliberate
  first-push materialization fix). Whether offscreen hybrid-composition views
  still cost per-frame compositing is unknown — residual suspect #1 if idle
  warmth persists; the follow-up would be remount-once-then-remove.

### Seen and deliberately left (NOTEs of record)

- `appbox_kit_overlay_extension.dart:346-355,496` — `.withOverlay()` defaults
  `isBlurred: true` (σ10–σ60) with ZERO call sites today; it becomes a
  blur-over-platform-views violation the day it is used. Before its first
  caller: flip the default to false or rebuild on
  `AppBoxKitFrostedSurface(platformViewSafe:)`.
- `showcase_notes_folder_view.mobile.dart:148-179` — note GROUPS build lazily
  (SliverList.builder) but each group eagerly inflates all rows; fine at seed
  scale, flatten rows into the sliver itemBuilder if folders grow.
- Vendor `experimental/glass_card.dart:85-104` — perpetual
  `repeat(reverse: true)` ticker, export-only with no callers; vendor tree
  left untouched per ADR-0002.

### Sweep all-clear highlights

- Zero direct `LiquidGlassContainer`/CN-view bypasses in the app (only the
  two main.dart route observers via the kit barrel); zero bespoke
  `supportsLiquidGlass` branches in app code.
- Every ticker/timer/animation bounded; the four prior fixes verified
  unregressed; the recorder's `elapsed$` 250ms ticker is created only in
  `start()` and cancelled in `_stopClock()`/`dispose()`.
- No blur stacking on the launch surface; xcscheme GPU validation confirmed
  stripped; `CADisableMinimumFrameDurationOnPhone` intentionally kept.
- Docs drift repaired: allowlist §3 rewritten post-ladder, step-1 test pin
  path corrected, three stale bullets in this report fixed, M3b/M5 comments
  re-scoped.

Verification: ui_library 405/405, showcase_app 161/161, `dart analyze` clean
on every touched file.

## Fifth pass — sheet consolidation + opaque/luminance/interference (2026-08-27)

Task: consolidate every showcase sheet on the one kit sheet, always opaque,
no luminance issues, content correctly wired, native glass inside sheets
never mis-rendering or overlapping other widgets. Two parallel audits
(census + internals) plus HIG Modality/Materials docs grounding.

### Already true (verified, no change)

- Every modal sheet in the app rides `appBoxKitShowSheet` with
  `opaqueGlass: true` (opaque `platformViewSafe` base); zero stock
  `showModalBottomSheet`, zero `opaqueGlass: false` callers. All sheet
  content verified wired (the resizable-sheet slider drives the
  heightFactor; attach rows pop results).

### Fixed (behavior-TDD, red-first)

- **Prompt dialog blurred over native buttons** —
  `appbox_kit_ask_surfaces.dart`'s iOS tier wrapped its body in the default
  σ20 BackdropFilter while hosting two CN platform-view buttons
  (flutter#175048 hazard + last translucent kit dialog). Now
  `platformViewSafe: true` + opaque tint, the alert-dialog recipe. Pin:
  `appbox_kit_notification_ask_test.dart` (`kit.ui-library.ask-surfaces —
  the prompt dialog panel is opaque and platform-view-safe`).
- **Photo lightbox bypassed the kit presentation path** —
  `showcase_note_photo_strip_widget.dart` showed a raw `showDialog` on the
  nested-router context (renders behind the shared tab bar) with no
  `anyModalDepth` bracket (native glass on the obscured page could composite
  above it — the reported "passing over" interference). Now presents from
  `StackedService.navigatorKey` root context with `useRootNavigator: true`
  and a `markAnyModalActive/Inactive` bracket. Pin:
  `showcase_note_photo_strip_widget_test.dart` (root-navigator coverage +
  depth bracket).
- **Sheet close button interfered with content** — the kit's glass xmark
  overlaid the body's top-right corner with no reserved inset (victim: the
  resizable demo's percent label). The body now reserves the button's zone
  (`_clearOfClose`, 52px less the grabber's 20 when drawn). Pin:
  `appbox_kit_native_sheet_test.dart` (content.top ≥ button.bottom).
- **Close-button luminance** — glass labels were measured washed out on the
  opaque sheet base (iOS 26.5 simulator, 2026-08-16, recorded in
  `showcase_components_input_bar_widget.dart:8-11`). The xmark now uses the
  filled-gray sheet-close idiom (`CNButtonStyle.gray` — contrast independent
  of backdrop sampling) with a pinned monochrome `label` symbol color. Pin:
  same test (`config.style == gray`).
- **Android drag leak** — `isDismissible: false` never forwarded
  `enableDrag`, so drag-to-dismiss leaked on the Material tier (iOS already
  forwarded). Now forwarded; pinned by drag-attempt test.

### Docs/config drift repaired

`appBoxKitShowNativeSheet` → `appBoxKitShowSheet` in `COMPONENTS.md`, the
usage appendix (×3), the review gate's fix-hint (`gates/review/review.dart`),
and `PLAYBOOK.md`; the sheet's stale "no app registers
CNTabBarRouteObserver" comment premise corrected (the showcase app does —
double-bump unwinds cleanly via the zero-clamp).

### Open for the device eyeball

- Gray close button + reserved clearance: verify light AND dark themes.
- Vendor tree untouched (per ADR-0002); theme-flip cure wiring was verified
  already correct on the sheet path (exempt in `check_theme_wiring.sh` — no
  channel — and the close button carries the full `CNAppearance` stack).

### Sheet NOTEs of record (audited, deliberately left)

- `appbox_kit_native_sheet.dart` `factor == null` branch is unreachable
  (unsized callers ride `_FixedHeight(0.56)`); kept as defensive shape, now
  consistent with the clearance wiring.
- Unpinned-but-stable branches: the σ30 `opaqueGlass: false` opt-out (zero
  callers, ADR 0011 keeps the option), `showCloseButton: false`, the 0.56
  default height, theme-flip tint re-resolution.
- Vendor `wrapWithModalInteractionGuard` is a reverted passthrough — under
  `showOverlay: false` host-page glass stays tappable beneath the sheet's
  clear area (every current caller uses the default `showOverlay: true`,
  where the dim barrier covers it).
- `AppBoxKitBottomSheetService` silently drops stacked's `enableDrag`/
  `isScrollControlled`/`barrierColor` knobs (zero direct callers in the
  showcase; map honestly or `debugPrint` when a caller next needs them).
- Glass-in-scrollable vendor contract now documented on
  `appBoxKitShowSheet`'s dartdoc (scrolling bodies use `wantNative: false`
  controls).
- Close-button clearance shipped as content padding (`_clearOfClose`); the
  structural alternative — moving the button in-flow into a chrome row with
  the grabber (nothing overlays anything) — was considered and deferred as
  churn-for-elegance while (a) is pinned and green. Revisit if chrome layout
  ever gets more complex. The attachment sheet's 'Attach' title row was a
  second latent overlap victim; the kit-side clearance covers it with no
  showcase change.

Verification: ui_library 408/408, showcase_app 162/162, `dart analyze`
clean on every touched file.

## Sixth pass (2026-08-27) — notes-shell luminance/cut sweep + the GLOBAL glass policy

Trigger: user saw residual luminance/cuts in the notes shell and asked for
the per-surface remedies to become automatic kit behavior. Run with
/systematic-debugging (Phase 1 census before any fix), /read-the-damn-docs
(the law doc + vendor contracts), /ultrathink-kimi L4 (K3 advisor,
confidence 0.82 — adopt mechanisms 1+2+3+5, scroll-demotion stays
gate/ladder-only).

### Census (subagent, 5 HARD + 2 SOFT) → dispositions

- **H1 pinned search bar in the folder CustomScrollView** — closed as lawful
  chrome (allowlist class 1: pinned sliver headers count as chrome), then
  REOPENED on device the same day: the pinned header's `minExtent 56 <
  maxExtent 72` visibly shrank/slid the bar on first scroll ("when scrolling
  the search bar moves — it must not"), and a UiKitView in a scrollable stays
  out of the vendored contract regardless of the chrome classification.
  FIXED by the originally-named remedy: the bar is hoisted OUT of the
  CustomScrollView into fixed Column chrome under the app bar
  (showcase_notes_folder_view.mobile.dart); ShowcaseNotesPinnedSearchBarWidget
  and its pin are deleted with it. Re-pinned at the behavior level by
  showcase_notes_folder_search_bar_fixed_test (scroll-invariant geometry).
- **H2 opaque `Material` slab behind the translucent native search bar**
  (showcase_notes_pinned_search_bar_widget.dart) — the visible "cut" band.
  FIXED: backing removed; superseded by the H1 hoist above (no sliver, no
  backing question at all).
- **H3/H4 glass social/auth buttons on the bright scaffold base** (auth +
  create-account panels) — the measured washout class. FIXED GLOBALLY by
  the luminance adaptation (below) — no showcase edits needed.
- **H5 audio-row icon button in the editor scroll** — lawful (ruling 4:
  controls native in scroll; editor carries the glass-law-exempt
  SingleChildScrollView ruling). Not a defect.
- SOFT: prominentGlass on bright bases (kept — CTA idiom; device check),
  top-edge scrim watch-item (already logged in rule 4).

### The global mechanisms (kit)

1. **Auto-opaque law** — `AppBoxKitFrostedSurface` takes the no-saveLayer
   branch for ANY fully opaque tint (rule 13's rationale codified; opacity
   is a mode switch — never animate tint alpha across 1.0).
2. **Modal auto-bracket** — verified pre-existing:
   `CNTabBarRouteObserver._isAnyModal` matches every PopupRoute, so raw
   `showDialog` self-brackets wherever the observer is registered (root +
   nested tab routers via `inheritNavigatorObservers` default). Explicit
   kit marks stay as defense-in-depth (Overlay entries). New pin:
   appbox_kit_native_modal_observer_test. Stale doctrine comments
   corrected (photo strip, gate hint).
3. **`AppBoxKitGlassLuminance`** — InheritedWidget; every frosted surface
   publishes `opaque` + `brightness`; `AppBoxKitNativeButton` /
   `AppBoxKitNativeIconButton` demote `glass` → `gray` + on-surface
   monochrome symbol ink on a bright opaque base. No scope → theme scaffold
   background decides (covers bare-Scaffold surfaces like the auth panel).
   Dark opaque keeps glass; prominentGlass never demotes;
   `luminanceAdaptive: false` escape hatch. 9 new pins.
4. **Gates** — `_nativeSurfaceBans` gains raw `showDialog(`,
   `showCupertinoDialog(/showCupertinoModalPopup(`, and `BackdropFilter(`
   bans (generic-arg forms covered); `showModalBottomSheet` regex extended
   to generic calls. Selftest 21/21; notes surfaces all green.

### Deliberate test re-seats (behavior change, not regressions)

- frosted-surface tint-override pin moved to a translucent tint (opaque
  tints now skip the blur by law).
- native-button "every style 1:1" + both glass-passthrough pins re-seated
  on a dark theme (they pin the enum mirror / scroll ruling; the
  bright-base remap is the luminance suite's job).
- icon-button default-glass pin re-seated on a dark base.

Device-verification queue: notes folder search-bar seam gone (light +
dark), auth social buttons gray-on-bright, editor/folder unchanged in
dark mode.
