# Native glass does not follow the in-app theme (bug B)

Evidence: `ScreenRecording_08-11-2026 11-29-11_1.MP4` (42.5 s, 1180×2556, debug
build), two theme flips on Home — dark at t≈8.75 s, light at t≈22.2 s. All calls
below are from **full-resolution crops**; 240 px contact-sheet tiles produced two
wrong readings (see Corrections).

## Symptom, measured

| Surface | Vendor component | 0.8 s after the flip | Converged |
|---|---|---|---|
| Bottom tab bar | `CNNativeTabBar` | light ✓ | immediate |
| FAB `+` | `CNPopupMenuButton` | light ✓ | immediate |
| Toolbar circles | `CNGlassButtonGroup` | light ✓ | immediate |
| Glass card (split-button card) | `LiquidGlassContainer` | light ✓ | immediate |
| **"Glass CTA" pill** | **`CNButton`** | **dark ✗** | ~3 s |
| **"Send" split button** | **`CNGlassButtonGroup`** | **dark ✗** | ~3 s |

## Leading candidate for the Glass CTA

`UIButton.Configuration` never re-resolved after a brightness change — see "Also
fixed" below. That is the mechanism with both in-repo precedent (the tint branch
already does it) and independent external corroboration, and it is device-only
verifiable. Read that section first; the Dart section below turned out to be
hardening rather than the fix, and says so.

## A second, real defect (hardening, not the fix — see the measured note)

`_syncBrightnessIfNeeded` must read the theme **before** it bails out on a null
channel. The read is what registers the State's dependency on
`Theme`/`CupertinoTheme`; without it `didChangeDependencies` never fires again for
an in-app theme change, and the view is **deaf, not slow** — it holds its
creation-time appearance until something else happens to rebuild it.

The repo already knew this. `glass_button_group.dart:184-189` carries the fix and
states the reason verbatim:

> Read the theme FIRST so this State registers an inherited dependency on
> CupertinoTheme/Theme even when the platform view (and thus the channel) hasn't
> been created yet. Bailing out before this read meant `didChangeDependencies`
> never re-fired for in-app theme changes.

`button.dart` — the "Glass CTA" — did the opposite: `final ch = _channel; if (ch ==
null) return;` *then* `final isDark = _isDark`. A null channel is the normal state
on the first `didChangeDependencies`, and for the entire `PlatformViewGuard` 500 ms
window in debug builds.

**Audit — 12 of 13 platform-view components had the defective shape**; the one that
did not is the one that restyles within a frame on device:

| Shape | Components |
|---|---|
| reads theme first ✓ | `glass_button_group` |
| bails first ✗ | `button`, `icon`, `liquid_glass_container`, `popup_menu_button`, `range_slider`, `search_bar`, `search_scaffold`, `segmented_control`, `slider`, `switch`, `tab_bar`, `text_field` |

Fixed uniformly: the theme read is hoisted above the bail in all 12.

> **Measured: this hoist is hardening, not the fix — at least for `CNButton`.**
> Mutation M1 moved the theme read back below the bail in `button.dart` and the new
> `cn.button` test **still passed**. So the dependency is already registered by
> something else on that component — `build` puts `_isDark` in its creation params
> (`button.dart:550`), which registers it on every build that reaches the
> platform-view branch. The hoist therefore does **not** explain the Glass CTA lag
> and must not be reported as its fix.
>
> It is kept because it is a one-line reordering that matches the one implementation
> with a documented reason, and it strictly widens dependency registration — it
> cannot regress. But it is a latent-hazard fix, load-bearing only for a component
> whose build reads no inherited theme, and no such component has been demonstrated
> here. `glass_button_group.dart` claims to have been one; that claim is inherited,
> not re-verified.

## Also fixed

**`setBrightness` targeted the wrong object on SwiftUI-hosted views.** Both the
working and the broken views attach as `container.addSubview(hostingController.view)`
with **no `addChild`** (`CupertinoButtonPlatformView.swift:778`,
`GlassButtonGroupView.swift:519`), so the hosting controller never joins the
view-controller hierarchy. `GlassButtonGroupView.applyBrightness` (`:641-644`) sets
`hostingController.overrideUserInterfaceStyle`; the other four set the *container*'s.
Now both, in `CupertinoButtonPlatformView`, `CupertinoSearchBarPlatformView`,
`CupertinoTextFieldPlatformView`, `FloatingIslandPlatformView`. Alignment with the
one implementation observed working — not independently proven.

**`UIButton.Configuration` was never re-resolved after a brightness change.** The
configuration bakes its resolved colours at assignment time, so a `.glass()` assigned
under the old appearance survives the trait change. `CupertinoButtonPlatformView`
already re-applies the style when the *tint* changes — "Re-apply style so
configuration picks up new base colors" (`:329`) — and simply never did it for
brightness. `setBrightness` now calls `applyButtonStyle(buttonStyle:round:)` with the
stored style (no-op on the SwiftUI tier, which the function guards). This is the
component behind the "Glass CTA", one of the two observed laggards, and it is an
independent mechanism from the Dart fix above — either alone could have produced the
symptom.

Corroborated outside this repo: **expo-glass-effect#43743** (accepted Mar 2026) is the
same bug in another project — `setColorScheme` set `overrideUserInterfaceStyle` but did
not call `updateEffect()`, so the glass stayed stale, while `setTintColor` and
`setInteractive`, which do re-assign the effect, updated immediately. No
`UIVisualEffectView`/`UIGlassEffect` exists in this package, so the literal fix does not
port; `UIButton.Configuration` re-assignment is the same shape.

**`ThemeHelper.getBrightness` mapped "follow the system" to hard light.**
`CupertinoThemeData.brightness` is nullable and null means *follow
`MediaQuery.platformBrightness`*; `theme_helper.dart:20` returned `?? Brightness.light`.
Now resolves the platform brightness in that branch — deliberately *there* and not by
falling through, because `Theme.of` does not throw when there is no `Theme` ancestor,
it returns the light `ThemeData.fallback()`, which would have re-introduced the same
bug one branch down. Latent: under `MaterialApp` the value is a
`MaterialBasedCupertinoThemeData` and is non-null.

## Not defects — deliberately left alone

- **`LiquidGlassContainerView.swift` has no `setBrightness` case.** It syncs via
  `updateConfig`, and the clip proves that path works: at t=23.0 the split-button
  *card* is fully light while the Send pill inside it is still dark. Adding a
  second mechanism to a working one is the shape this repo has already regretted
  twice.
- **`CNNativeTabBar`, `CNPopupMenuButton`.** Both restyle within a frame. An earlier
  read of the thumbnails put them in scope; they are out.

## Open — not root-caused

**The "Send" split button.** It is `CNGlassButtonGroup(buttons: [action, menu])`
(`split_button.dart`), i.e. *the same class as the toolbar*, which restyles within a
frame — and it carries the correct theme-first sync. Same class, same fix, one lags
and one does not. Nothing in this document explains it, and the fixes above are not
claimed to.

Narrowed as far as source allows. Both instances are unioned glass: the toolbar
passes `glassEffectUnionId: union` (`appbox_kit_native_toolbar.dart:138`) and
`CNSplitButton` passes `glassEffectUnionId: _union` (`split_button.dart:75`), so the
union is not the difference either. The **only** structural difference left is that
the split group's second half is a `CNButtonData.popup` and the toolbar's are plain
and icon buttons. That is where an instrumented run should look first.

The next lever if it does turn out to be SwiftUI-side is `.id(...)` keyed on the
colour scheme over the `GlassEffectContainer`, which forces a full rebuild rather
than an invalidation. Deliberately **not** applied blind: this is a view whose Dart
*and* Swift sides both already look correct, so adding a third mechanism on
speculation is the move this repo has twice had to undo.

Also unexplained: why both laggards recover **together** after ~2–3 s with no input.
Two independent native caches (a UIKit `.glass()` configuration and a SwiftUI
`GlassEffectContainer`) share no invalidation path, so a common recovery points at a
Dart-side trigger; no timer in kit or vendor matches, and the transition-observer
watchdog (`transitionDuration + 1000 ms`) is not armed by a theme flip.

**Next step is one instrumented device run**, not another static hypothesis — six
were formed and five died against the evidence. Log on both sides of the boundary:
Dart, immediately before `invokeMethod('setBrightness')` (component, `isDark`,
`_lastIsDark`); Swift, on entry to the handler. One run of the same two flips answers
whether Dart sends at t≈22.2 and native ignores it, or Dart does not send until
t≈26 — which collapses the remaining space.

## Verification

`brightness_sync_test.dart` drives the real `UiKitView` creation handshake and spies
on the per-view channel, so the Dart→native contract *is* assertable headless. It
covered only `CNTextField` and `CNSearchBar` — the two components fixed when it was
written — which is why this survived. Now also covers `CNButton` both ways (dark→light
→dark) plus a same-brightness rebuild, so a fix that hard-codes a value fails.

What no headless test can reach: whether the glass actually re-blurs. That is a
device check, and the user can re-shoot the same flip.
