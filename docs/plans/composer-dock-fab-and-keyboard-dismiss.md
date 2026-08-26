# Composer dock: FAB position, home-indicator clearance, keyboard dismissal

Follow-up to `bottom-dock-handoff.md`. Three reports from one screenshot
(Profile → Components, 2026-08-11 15:03): the FAB had moved and now overlapped
the composer's mic button; the composer sat flush on the screen edge instead of
riding higher like a chat composer; and there was no way to tap out of the
keyboard.

## 1. The FAB moved — regression from the tab-bar yield

**Root cause.** The FAB's clearance never came from the tab bar being a *bar*.
`ArxaKitExtendBodyFabLift` mirrors the `extendBody`-injected bar height into
`viewPadding.bottom`; `FloatingActionButtonLocation` derives `safeMargin` from
`minViewPadding.bottom` (`floating_action_button_location.dart:566`). Remove
the bar and that band disappears, so the FAB dropped ~80pt onto the composer.

**Dead end worth recording.** The first fix was a kit
`ArxaKitFabAboveDock` — a `FloatingActionButtonLocation` overriding
Material's deliberate half-straddle (`fabY = min(fabY, contentBottom -
sheetHeight - fabHeight / 2)`, `:577-579`). It was written, tested, wired, and
**measured to do nothing**: the composer is a `bottomSheet` on the *Components*
Scaffold, while the FAB belongs to the *gallery chrome* Scaffold above it, so
that Scaffold's `bottomSheetSize` is `Size.zero` and no location on it can ever
see the dock. Deleted rather than kept as a widget whose doc claimed a case it
did not fix.

**Actual fix.** Keep supplying the band from above: `_DockFabLift` in the tab
host raises `viewPadding.bottom` by `kShowcaseTabBarBlockHeight` while the
active tab's top route docks its own bar. `viewPadding` only — `SafeArea` and
every content-inset consumer read `padding`, so this cannot shove content.
Measured: FAB bottom 730, composer top 746 — clear, and 730 is exactly where
the FAB sat before the regression.

**The lift is a constant, and that is checked, not assumed.** It adds
`kShowcaseTabBarBlockHeight` on top of the existing `viewPadding.bottom` rather
than the dock's measured height — the tab host cannot see into a nested route.
The obvious worry is that it only clears because a 34pt indicator makes the
numbers work; it does not. The composer's height tracks the same inset, so both
sides move together: measured, the gap is 16pt at a 34pt indicator **and** at
zero. Tested at both. The real ceiling is a dock *taller* than the constant — a
multiline composer would under-clear, and that is the day to plumb a measured
height up.

> **`_DockFabLift` always wraps.** The first version early-returned `child`
> when the lift was 0. That flips the tree *shape* between builds, the Element
> below is not reused, the whole tab stack remounts, and the nested routers lose
> their stacks — the Components push was silently dropped and the app bounced to
> the tab root. Same shape as C4 in `glass-chrome-root-cause-fixes.md`. A `+ 0`
> MediaQuery is free; the early return is not.

## 2. Composer sat on the home indicator

**Root cause — two Scaffolds, each stripping the inset.** Measured at the
composer: `padding.bottom == 0.0` **and** `viewPadding.bottom == 0.0`.

1. The tab bar yielded as a zero-height `SizedBox`. Scaffold removes the body's
   bottom padding whenever `bottomNavigationBar != null` (`scaffold.dart:3032`)
   — a shrunk-but-present bar still counts, so it consumed the inset and gave
   nothing back. Now `null`.
2. The Components Scaffold left `resizeToAvoidBottomInset` at its default
   `true`, and the `bottomSheet` slot is registered with
   `removeBottomPadding: _resizeToAvoidBottomInset` (`scaffold.dart:3086`).
   Now `false`, which is also correct on its own terms: the bar rides the
   keyboard itself, so the Scaffold must not also resize.

`MediaQueryData.removePadding` subtracts the consumed amount from `viewPadding`
too (`media_query.dart:946-951`), which is why nothing downstream could recover
it.

> **Correction.** An intermediate fix changed the kit's
> `ArxaKitNativeInputBar` to pad by `max(viewInsets.bottom,
> viewPadding.bottom)` instead of a `SafeArea`, on the premise that
> `viewPadding` survives ancestor consumption. It does not — `removePadding`
> reduces both. That change was measured to have no effect and was reverted;
> the kit widget is untouched. Both real causes are at the two call sites.

Result: `padding.bottom` arrives as 34, the bar grows 64 → 98, and its content
sits 42pt off the screen edge.

## 3. Tap out to dismiss the keyboard

**The trap.** `CNTextField` is a `UiKitView` whose focus lives in SwiftUI's
`@FocusState`, and it carries **no `FocusNode`** — verified, there is no
`Focus`/`FocusNode` anywhere in it. So `FocusManager.instance.primaryFocus
?.unfocus()`, which is what every published recipe uses
([apparencekit](https://apparencekit.dev/flutter-tips/flutter-dismiss-keyboard-on-tap/),
[LogRocket](https://blog.logrocket.com/how-to-open-dismiss-keyboard-flutter/),
[KindaCode](https://www.kindacode.com/article/flutter-dismiss-keyboard-when-tap-outside-text-field)),
has nothing to unfocus and silently leaves the keyboard up on exactly the field
in the screenshot. The native lever existed all along (`case "unfocus"` →
`focusBinding.relinquish()` in `CupertinoTextFieldPlatformView.swift:132`) and
was never called from Dart.

**Shape** (user's call: minimal over a full `FocusNode` rewrite):

- `CNTextFieldFocus` (vendor) — one nullable `MethodChannel`, maintained by the
  `focusChanged` callback the native side already sends, cleared in `dispose`
  for the unmount-while-focused path. One variable, not a registry: only one
  field can hold the keyboard. No listeners, so it cannot notify mid-build —
  the hazard fixed earlier in `modal-depth-notify-during-build.md`.
- `ArxaKitDismissKeyboard` (kit) — the app-wide lever, wrapped once around
  the app in `main.dart`. Fires **both** paths.
- `context.dismissKeyboard()` — the imperative extension. Noted because the ask
  was for "an extension": an `extension on BuildContext` cannot *install*
  behaviour app-wide, so the widget is what "apply in main" requires; both ship.

**`Listener`, not `GestureDetector`.** A detector competes in the gesture
arena, and an ancestor that wins swallows the tap — the button under the finger
never fires. `Listener.onPointerDown` observes the raw pointer before arena
resolution, so it never competes. It also matches iOS, which closes the
keyboard as the finger lands. Tested: the button still receives its tap on the
same gesture that dismisses.

## Verification

Mutations, run on a committed tree (the loop aborts on a dirty one):

| Mutation | Result |
|---|---|
| drop the dock FAB lift | fails ✅ |
| `_DockFabLift` early-returns `child` (shape flip) | fails ✅ — and takes the whole route with it, which is the point |
| Components back to default `resizeToAvoidBottomInset` | fails ✅ |
| dismisser drops the native tier (i.e. the stock recipe) | fails ✅ |
| dismisser drops the Flutter unfocus | fails ✅ |

Suites: vendor 121, ui_library 311, showcase 124; analyze clean in all three.
(ui_library went 307 → 314 → 311 across the round: dismiss-keyboard tests
added, the fab-above-dock ones deleted with the widget.)

**The native keyboard dismissal has no hardware evidence.** It is asserted by
mocking `CNTextField`'s method channel — a `UiKitView` cannot mount in a widget
test, so no real keyboard was ever raised or closed. Everything else here is
geometry, measured headless and reproducible; this one part, which is the part
specifically asked for, is verified only as far as "the dismisser calls the
channel the native side listens on." It wants a device check.

Also headless-only in the weaker sense: `supportsLiquidGlass` is false in tests,
so the tab bar exercised is the fallback, not `CNTabBar`.

## Drag-to-dismiss: already delivered, not added

`ScrollViewKeyboardDismissBehavior.onDrag` was offered as a free extra and then
**not** added, because measuring showed it was already covered and would have
been the weaker of the two mechanisms:

- `ArxaKitDismissKeyboard` listens on `onPointerDown`, and a drag begins with
  a pointer-down — so scrolling any list already dismisses, app-wide, on both
  tiers. Tested: the drag dismisses **and** the list still scrolls.
- The built-in would not be equivalent. `Scrollable`'s onDrag calls
  `FocusManager.instance.primaryFocus?.unfocus()` and nothing else, so it is
  blind to the native `CNTextField` tier — the exact half-failure this work
  exists to remove. Adding it would have been a second, weaker authority for
  one event.

## Coverage gap this turned up

Every showcase test boots via `bootShell`, which pumps `MaterialApp.router`
directly and never builds `ShowcaseApp` — so nothing covered the one line in
`main.dart` that installs the dismisser app-wide. Deleting that line kept the
entire suite green. `showcase_app_keyboard_dismiss_wiring_test.dart` now
asserts the widget is present *and* is an ancestor of the `MaterialApp`, since
installing it underneath would cover only whichever route built it.

Mutations:

| Mutation | Result |
|---|---|
| remove the wrapper from `main.dart` | fails ✅ (kept the suite green before this test existed) |
| `Listener` → `GestureDetector(onTap:)`, i.e. the published recipe | fails 2 ✅ — the drag no longer dismisses and the tap gets swallowed |
