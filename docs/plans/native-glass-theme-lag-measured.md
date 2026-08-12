# Native glass theme lag — what the 20:16 clip actually measures

Device clip: `ScreenRecording_08-11-2026 20-16-30_1.mov`, 1180×2556 @ 60fps, 47.9s,
DEBUG build. Four in-app theme flips (segmented control taps), at t = 2.645,
7.322, 14.410, 18.570, 22.863, 25.258.

Everything below is measured from that clip frame-by-frame, not inferred.

## 1. The previous fix works. It is not the whole bug.

`themeAnimationDuration: Duration.zero` (commit `ac04ced`) landed at 20:09, the
device `App.framework` is stamped 20:14, the clip is 20:16. It is in the binary.

Whole-frame luminance steps **in a single frame** at every flip (29 → 202 at
t=2.645). With the old 200ms animation this would have been a ~12-frame ramp.
Of 1222 cells that change, **1009 change on the same frame**. The Flutter half
of the UI now flips instantly, as intended.

The remaining bug is entirely in the native half.

## 2. Per-element lag, flip 1 (dark → light)

Lag measured from the frame the Flutter surfaces flipped.

| element | lag |
|---|---|
| segmented control | 0 ms |
| app-bar search, icons 1–5 | 367 ms |
| tab bar | 383 ms |
| "Send" split | 683 ms |
| app-bar "…", Glass CTA, "+" | 1134–1150 ms |
| icon 6 | 1867 ms |
| icon 7 | 2117 ms |

## 3. The shape: flat, then a step. Never a ramp.

This is the single most important measurement, and it splits the bug in two.
Per-frame luminance for each laggard is **flat at its old value, then steps**:

| element | starts changing | duration of the change itself |
|---|---|---|
| icon 1, tab bar | ~300 ms | ~200 ms |
| Glass CTA, "…" | ~1000 ms | ~250 ms |
| icon 6 | ~1700 ms | ~200 ms |
| icon 7 | ~2100 ms | ~200 ms |

So the **application** of the new appearance is uniform (~200–300 ms for every
view). What varies — by up to 2.1 seconds — is **when a view starts**.

Two distinct defects, and only the second is large:

- **B1 — the ~250 ms step.** Uniform, every view, both directions.
- **B2 — the start delay.** 0 ms to 2117 ms, non-deterministic.

## 4. B2 is non-deterministic, which rules out "a broken component"

Same screen, same gesture, different flip:

| element | flip 1 | flip 2 |
|---|---|---|
| app-bar "…" | 1134 | **350** |
| icon 7 | 2117 | **350** |
| "+" | 1150 | **367** |
| Glass CTA | 1134 | 850 |
| icon 6 | 1867 | 1850 |

Light → dark is faster overall (median 200 ms) but equally erratic: the search
button took 1717 ms in one flip and 450 ms in another; the Glass CTA took
1950 ms in one and **0 ms** in another.

A view that can update in the same frame is not structurally broken. Whatever
B2 is, it is a scheduling property, not a per-component defect. Every
"component X is missing Y" theory is therefore excluded on this evidence alone.

## 5. Nothing is saturated

- **Dart is prompt.** A channel probe over one flip: every `setBrightness`
  lands in **frame 0**, the same frame as the flip. 20 channel calls, all
  frame 0. (Probe deleted after it answered.)
- **The app renders at 59fps.** Measured from the segmented-control selection
  indicator, which physically slides on the tap: its centroid advances on
  *every* frame (15.6 → 16.7 → 18.1 → 19.2 → 20.2 → …) and 40 of 41 frames in
  the window differ. Global frame diff is non-zero continuously from f=39 to
  f=147, so frames keep being produced across the whole 2.1 s.

So: the command is delivered immediately, the device is not janking, and the
visual change still starts up to 2.1 s later. **B2 is the native side
deferring the change**, not late delivery and not lack of capacity.

### Retracted mid-investigation

An earlier reading of this clip claimed "the UI thread is not frozen" from a
spinner ticking at a regular 117 ms. That box was contaminated by the card
background transitioning behind it, and in a quiet period the same box shows
**one** change in 3 seconds — it is not a clock. The conclusion happened to be
right, but the evidence for it was not; it is re-established above from the
sliding indicator, which is a real Flutter animation.

## 6. B1 has a named cause

`CupertinoButtonPlatformView.swift:840-857` — `applyButtonStyle` assigns a
**fresh `.glass()` configuration**. The repo's own note, from WWDC25 #284:

> establishing glass materializes with an animation by Apple's design
> — `lib/utils/transition_observer.dart:284`

Re-establishing glass on every brightness change buys that materialization
animation every time. That is the uniform ~250 ms step, and it matches the one
component that does **not** do it: the tab bar's `setBrightness`
(`CupertinoTabBarPlatformView.swift:896`) is a single line —
`container.overrideUserInterfaceStyle = …` — and the tab bar is consistently
among the fastest. No `setBrightness` path anywhere suppresses implicit
animation; `UIView.performWithoutAnimation` appears in exactly one file and
only on the creation path.

Note this cuts against the author: the `applyButtonStyle` re-application was
added at 18:01 this same day. It is *correct* — `UIButton.Configuration` bakes
resolved colours at assignment, so it must be re-applied — but it is
unsuppressed, so it pays for an animation nobody asked for.

## 7. B2 — cause identified from external evidence, fix applied, unconfirmed

A hybrid-composition platform view lives in the native hierarchy *above*
`FlutterViewController`, **outside Flutter's own render pipeline**. Its layer is
therefore not necessarily re-composited when only Flutter-side state changes; a
scroll or a touch forces the pass, and the appearance change "catches up" then.

That is the non-determinism. Whichever view a Flutter repaint happens to touch
updates on time; the rest wait for some incidental pass. It also retro-explains
the *original* symptom this whole investigation started from — "some glass UI is
still dark, and it fixes itself a while later while navigating" — which is
almost verbatim [flutter#69104](https://github.com/flutter/flutter/issues/69104),
where a `UiKitView` "recovers after other operations such as switching pages and
going back".

Corroborating, for the glass specifically:
[expo/expo#43743](https://github.com/expo/expo/issues/43743) —
`overrideUserInterfaceStyle` updates the trait collection but `UIGlassEffect`
does **not** re-render in response; the effect must be re-assigned.
`setTintColor`/`setInteractive` re-assign and update instantly; the colour-scheme
setter did not, and the glass stayed dark until remount.

**Fix applied:** `Utils/CNAppearance.swift` now forces `setNeedsLayout` +
`layoutIfNeeded` + `setNeedsDisplay` synchronously on every affected view
(container, button, and the hosting controller's view — separate layer trees)
inside the same animation-suppressed transaction. This is the package's own
creation-path idiom (`CupertinoButtonPlatformView.swift:263-272`, `:815-824`)
applied to the per-flip path, and synchronously rather than hopped to a later
run-loop turn, since a deferred force is the bug rather than the fix.

**Status: not confirmed on device.** This is an evidence-backed fix for a
mechanism that matches every measurement, not a verified one. The tracing below
exists to confirm or refute it on the next run.

Rejected on the same evidence: render-server serialisation of glass
re-rasterisation across N views (7 × ~300 ms ≈ the 2.1 s span). Arithmetically
attractive, but it cannot produce a 0 ms onset for the same view on another
flip, and §4 shows exactly that.

Candidates **excluded by measurement**, recorded so they are not re-tried:

- Late Dart dispatch — probe shows frame 0 (§5).
- Main/platform thread saturation — 59fps (§5).
- Missing brightness sync on a component — non-determinism (§4).
- Platform-view recreation by key or creation param — no key or param carries
  brightness (grep, `button.dart` `resolutionKey` = `('custom', icon, size)`).
- Icon re-rasterisation on colour change — `button.dart:347` and
  `icon.dart:110` key resolution on `(icon, size)` with **no colour**, so a
  theme flip cannot invalidate them. (`glass_button_group.dart`'s digest *does*
  carry `iconColor` and `tint` — real, and it is a genuine cost for that
  widget, but it cannot explain plain `CNButton`/`CNIcon` laggards.)
- The 350/1000 ms constants in `transition_observer.dart` matching the observed
  350/1134 clusters — coincidence: per-view `setTransitioning` is driven by
  `_secondaryRouteAnim`, a route animation, and there is no navigation during a
  theme tap.

B2 cannot be closed headlessly. Nothing in a widget test can observe when a
`UIView` actually repaints. It needs one instrumented device run.

## 8. Latent, separate from the clip

- `floating_island.dart:378` passes `isDark` from `Theme.of(context)` as a
  **creation parameter only** — the exact original bug class (view pinned to
  its creation-time appearance). No consumer in `ui_library`/`showcase` today,
  so it is not in the clip, but it is live in the vendor package's public API.
- `native_tab_bar.dart:209` exposes `setBrightness` as a **static, manually
  driven** API with no automatic theme sync. Also unconsumed today.

## 9. Scope

`kit/showcase_app/lib/main.dart` is still the only app root embedding this
tier. No scaffolder template emits an app root, so generated apps do not
inherit `themeAnimationDuration: Duration.zero` and must carry it.

## 10. The 21:25 clip — verdict and the three leaks it exposed

Device clip: `ScreenRecording_08-11-2026 22.MP4` (1180×2556, 21:25), recorded
after `ac04ced`, `5126d9d`, `517844d`. Staleness was still on screen — some of
it for ≥13 s, longer than anything B2 measured — plus defects outside the lag
class entirely. Fixed against this evidence:

- **Popup buttons never re-resolved their configuration.**
  `CNPopupMenuButton.setBrightness` set the trait override but never re-applied
  `applyButtonStyle`, so its `.glass()` `UIButton.Configuration` kept the
  colours baked at creation — the "…" and "+" pills held white ≥13 s into
  dark mode, and dark into light. Now re-applies inside the same
  `CNAppearance.applyInstantly` wrapper, mirroring
  `CupertinoButtonPlatformView`. (macOS needs no parallel fix: the NSView
  handler assigns `NSAppearance`, which propagates on its own.)
- **Glass cards** (`LiquidGlassContainerView.updateConfig`) re-rooted the
  SwiftUI view with no animation suppression and no forced layout — cards
  held the old appearance for seconds. Now wrapped in `applyInstantly` like
  the four button-family handlers.
- **Hard-coded light-ramp colours in the showcase** — not a native defect at
  all. `ShowcaseSectionLabelWidget` used `const AppBoxKitColors.muted`, so
  RADIUS / PRICE RANGE / NAVIGATION RAIL / TOOLBAR went near-invisible in
  dark mode; the snackbar smoke-row icons forwarded fixed light-ramp tints to
  the native glyph/tint. Both now resolve from the active theme, pinned
  (mutation-checked) by `showcase_theme_adaptive_colors_test.dart`. Note the
  harness lesson: a widget test that flips themes via a second `pumpWidget`
  must set `themeAnimationDuration: Duration.zero`, or `AnimatedTheme` leaves
  the "dark" pump showing the light scheme at t=0 — the test re-creates the
  very desync under test.
- **`CNFloatingIsland`** passed `isDark` as a creation parameter only — the
  §8 latent case — and now syncs like the other components. Not covered
  headless: its native path gates on `PlatformVersion.isIOS26OrLater`, which
  is never true under `flutter test`. Device-checkable only.

Left alone, deliberately: the tab bar's bare one-line handler (§6's fast
path), the segmented/slider/switch/search/text-field bare handlers (nothing
in the clip pins a defect on them), the popup-`Menu` chrome ceiling
(FB13391355 — follows the OS trait when it disagrees with the in-app theme),
and the lerping-tint channel storm (`Duration.zero` removes it in the only
app root).

**Still needs one device run:** whether the instant-apply + config re-apply
fully close the residual multi-second staleness. Run with
`CN_TRACE_APPEARANCE=1` (Xcode scheme → Run → Arguments → Environment
Variables) and filter the console on `CNAppearance` if anything still lags.

## 11. The 22:51 clip + simulator runs — narrowing to the architecture

Device clip: `ScreenRecording_08-11-2026 22-51-09_1.MP4` — recorded on a
binary that contains the §10 fixes (the colour repairs are visibly live:
icons bright in dark, section labels readable). Verdict: **§10's colour and
coverage fixes hold, but the lag itself persists.** A non-deterministic
subset (Glass CTA, one icon circle, Send, "+", "…", toolbar — a different
set per flip) held the old appearance for 6–9 s and every laggard recovered
exactly on scroll/navigation. The B2 signature, still alive after
`applyInstantly` — UIKit-side forcing does not reach the screen.

Simulator runs (iPhone 17 probe, iOS 26.5, debug build with these fixes),
theme in `system` mode, appearance flipped via `simctl ui` with screenshots
at +0.4/+1/+3/+8 s: **full, correct convergence in ≤1 s, both directions, no
scroll.** The device lag does not reproduce under the simulator's software
rasterizer. (Side observation: zero `CNAppearance` prints reached the
`flutter run` log even though the UI flipped — native `print` forwarding is
not reliable there; use Console.app / `log stream` on device.)

What this splits, and it is the load-bearing question after three fix rounds:

- The **OS-appearance path** — the window's trait collection changes, every
  native view restyles through the normal hierarchy, render server
  cooperates — is flawless (simulator, and by design on device).
- The **in-app override path** — 13 components each pinning
  `overrideUserInterfaceStyle` per view + re-applying config + forcing
  layout — is the one that lags, non-deterministically, on hardware only.

So the candidate architectures are:

- **C — window-level override.** One `window.overrideUserInterfaceStyle`
  (Apple: on a window it covers "everything in the window, including the
  root view controller and all presented content"), driven once per flip by
  the theme service; per-view `setBrightness` stays only for creation-time
  params. Makes an in-app flip travel the *same* pipeline as an OS flip.
  Side effect: would also lift the popup-`Menu` chrome ceiling
  (FB13391355), since the Menu follows the window trait.
- **A — per-view structural re-render** (the `.id(colorScheme)` lever over
  the `GlassEffectContainer`, or re-assigning the effect, expo#43743-style):
  keeps the per-view architecture, fights the render-server material cache
  view by view.
- **B — platform-view recreation on flip** (key bump): definitive,
  flickery, last resort.

**Decisive experiment before any more code (20 s, no build):** on the
device, app in **Auto** mode, flip the OS appearance from Control Center
twice while watching the glass. If OS flips are instant on hardware → the
per-view override architecture is the defect, build C. If OS flips lag too
→ the deferral is below the app (Metal platform-view compositing), build A.

## 12. Round 3 — the 23:59/00:01 clips, the experiment, and the structural fix

Clips: `ScreenRecording_08-11-2026 23-59-17_1.mov` (icon rows close-up) and
`ScreenRecording_08-12-2026 00-01-22_1.mov` (cards + split close-up), on the
23:29 trace build. Two facts fell out:

- **The 00:01 clip is the controlled A/B.** The glass *cards* — re-rooted
  `rootView` since §10 — flip **on the frame**, while the Send pill *inside
  the same card region* held the old appearance 0.5–2.2 s per flip. Same
  flip, same region, same handler family: the only difference left is
  structural replacement vs in-place mutation.
- **The 23:59 clip kills the per-component theories.** The four row-1 icon
  buttons plus row-2's first flip fast on *every* flip; row-2's last two lag
  on *every* flip — same class, same handler, same params. A per-instance
  lottery is stable per instance: whatever governs re-composite order, it is
  not anything a per-component fix can reach.

The §11 experiment's verdict: **OS flips lag too** (confounded — in Auto the
app converts an OS flip into the per-view `setBrightness` storm anyway, so
the window pipeline was never isolated; treat "C is dead" as inferred, not
measured). Either way the path forward is the same, and the cards already
proved it on hardware:

> **Glass materials on hybrid platform-view layers do not re-sample when
> traits/config mutate existing layers; new layer content composites
> immediately.** Plain non-glass controls (switch, sliders, segmented track)
> flip fine with a bare trait pin — there is no material to re-sample.

Applied per glass-bearing class (architecture A, uniform):

- `GlassButtonGroupView.applyBrightness` — now **re-roots**
  `hostingController.rootView` (was: `@Published` invalidation only — same
  view identity, the lottery case). Send split + toolbar.
- `CupertinoSegmentedControlPlatformView.setBrightness` — now wrapped in
  `applyInstantly` and calls `rebuildSegments()` (fresh segment layers; the
  iOS 26 selection lens is glass — the 22:51 clip's double-highlight was the
  lens's frozen frame composited next to the live one). `rebuildSegments()`
  now preserves `selectedSegmentIndex` across the rebuild —
  `removeAllSegments()` resets it to `noSegment`, a latent selection-erase
  on the `setStyle` path too.
- `CupertinoButtonPlatformView` / `CupertinoPopupMenuButtonPlatformView`
  (UIKit `.glass()` tier — icon circles, Glass CTA, "…", "+" FAB) — after
  the config re-apply, the button **leaves and re-enters the hierarchy**
  (edge pins re-created): the layer's render-tree representation is torn
  down and re-created, which composites immediately. Same view object —
  content, targets, menus, handlers untouched. `kimitail:` if a re-add ever
  proves insufficient on device, the next lever is full button *replacement*
  (new view object, new layers) — more invasive, not needed yet.

Deliberately untouched: the CNButton **SwiftUI tier** re-root (no showcase
consumer passes glass ids — unverifiable here), `CNFloatingIsland`'s native
re-root (no consumer at all), CNIcon (renders no material), and every plain
control. The tab bar keeps its bare fast path.

**Status: awaiting the next device clip.** What to watch: Send pill and
segmented (structural, expected instant) vs any residual laggard. If a
UIKit-tier button still lags, the re-add was insufficient and the lever is
full button replacement.

## 13. The 01:29 clip — menu-bearing glass still lags; the teardown fix

Verdict on round 3 from the 01:29 device clip: **much better, not done.**
Icon circles, Glass CTA, segmented, cards — on-frame both directions. The
three laggards are exactly the **menu-bearing** controls: the Send split
pill (SwiftUI `Menu` segment), the "+" FAB and the "…" app-bar button (both
`showsMenuAsPrimaryAction` UIKit buttons). All three held the old material
for seconds — the Send pill was still stale ~9s into dark — and all three
recovered **exactly on scroll**, the incidental re-composite signature.

So the round-3 levers (style re-apply + re-add; rootView re-root) cured
menu-less glass but not menu-bearing glass. Root cause, confirmed outside
this repo: **re-assigning a value-equal glass configuration is a no-op —
the backing effect view survives with its pinned appearance.**
expo#43743 root-caused it (`UIGlassEffect` does not re-render on trait
change; "we need to set the effect again or it has no effect!") and shipped
the fix in expo-glass-effect 55.0.8; RN-screens#4081 traced the stale state
to UIKit's private glass interaction (`glassUserInterfaceStyle` stuck) and
notes Apple fixed it in iOS 27. No public report isolates the menu
attachment as a separate cause — treat the menu as an aggravator (context-
menu interaction keeps its own preview/morph machinery on the button), not
a second bug.

Applied (architecture A, uniform teardown — round 4):

- `CupertinoPopupMenuButtonPlatformView.setBrightness` ("…", "+" FAB) —
  before the style re-apply, commit a **non-glass background**
  (`cfg.background = .clear()` + `updateConfiguration()`), forcing the stale
  effect view out; the re-apply then builds a FRESH one in the new trait.
  Never via `nil`/effect-toggle — a no-op for glass. Re-add lever kept.
- `CupertinoButtonPlatformView.setBrightness` — same teardown, gated
  `!usesSwiftUI`, so the whole UIKit `.glass()` tier shares one mechanism.
- `GlassButtonGroupView.applyBrightness` (Send pill) — the SwiftUI
  equivalent: new `@Published appearanceEpoch` fed to `.id(...)` on the
  body root. `isDark` + re-root alone left the glass diffed-but-reused
  (modifier values unchanged → backing effect views survive); the epoch
  forces destruction + recreation of the subtree.

Watch-list, deliberately untouched: CNButton **SwiftUI tier** (no showcase
consumer passes glass ids — unverifiable here), `CNFloatingIsland` (no
consumer), CNIcon / search / textfield / switch / sliders (no glass
material), tab bar (bare fast path, measured fastest), segmented (already
on-frame via `rebuildSegments`).

**Status: awaiting the next device clip.** Watch order: Send pill, "+"
FAB, "…" (teardown, expected instant). If a menu-bearing UIButton still
lags, the committed next lever is full button *replacement* (new instance =
new interaction objects + new layers; expect a one-frame light flash per
RN-screens#4163, mitigated by applying inside `applyInstantly`). If the
Send pill still lags, replace the hosting controller itself.

## 14. The 02:31 clip — Send pill cured; replacement for menu buttons; the tab bar joins

Verdict on round 4 from the 02:31 device clip: **the Send pill is perfect** —
the `.id(appearanceEpoch)` teardown flips it on-frame every time, both
directions. The config-teardown on the UIKit tier did NOT cure the
menu-bearing buttons: `…` and `+` still held the old material for seconds
(dark-into-light at 20s/47s, light-into-dark at 40s/50s), recovering on
scroll. And one new laggard surfaced: the **native tab bar** (white bar
seconds into dark at 50s, dark into light at 47s) — the "bare trait pin is
the fastest path" belief was earlier-clip luck; the iOS 26 UITabBar is
glass and loses the same re-composite lottery.

Round 5, per the escalation the evidence demanded:

- `CupertinoPopupMenuButtonPlatformView.setBrightness` — **full button
  instance replacement** (`replaceButtonForThemeFlip`). Lesser levers are
  now doubly measured-insufficient for menu-bearing buttons (re-add: 01:29;
  config teardown: 02:31) — the context-menu interaction pins the button's
  composited material below anything a configuration or hierarchy nudge
  reaches. A new `UIButton` gets new layers AND a new interaction. All
  state is rebuilt from fields (style/icon/symcfg/menu/update handler) or
  copied (tint/interaction/clip/shadow/title); the fresh button is fully
  configured before entering the hierarchy, inside `applyInstantly`, so no
  intermediate frame renders (RN-screens#4163's flash came from deferred
  recreation). `configurationUpdateHandler` extracted to
  `attachConfigurationUpdateHandler` so init and replacement share it.
- `CupertinoTabBarPlatformView.setBrightness` — no longer bare: wrapped in
  `applyInstantly` + **constraint-capturing re-add** of the bar(s). Pins
  are collected before removal (inter-bar split constraints are
  container-owned and shared between bars; self-owned width pins survive
  removal), so the split layout needs no re-derivation.

Deliberately untouched: `CupertinoButtonPlatformView` (menu-less CNButtons
verified on-frame across all four flips in this clip — teardown + re-add
stays), segmented (on-frame; the 47s smudge is the touch lens under the
user's finger, not the frozen-frame artifact), cards, icon, search,
textfield, switch, sliders, CNButton SwiftUI tier, FloatingIsland (both
consumer-less). `kimitail:` if the tab bar still lags next clip, its lever
is full `UITabBar` replacement (items/selection/appearance rebuild) — not
done now because re-add is proven sufficient for every menu-less glass
control so far.

**Status: awaiting the next device clip.** Watch: `…`, `+` (replacement,
expected instant), tab bar (re-add, expected instant), and confirm the
Send pill stays perfect.

## 15. The 10-11 clip — menu buttons + tab bar cured; the segmented lens; uniformity sweep

Verdict on round 5 from the 10-11 device clip (full-res frame crops):
**FAB, "…", and the tab bar all follow every flip** — instance replacement
and the constraint-capturing re-add cured them. The one persistent defect
left: the segmented control's **selection lens smearing** — frozen
semi-transparent lens fragments on the segments it slid over, visible 1–2s
at rest (5.5s: smears on Auto+Light after Dark tap; 11.7s: pill frozen
mid-flight between Auto/Light), clearing later. Mechanism: the flip is
triggered by a tap on THAT control, so the lens slide is always mid-flight
when `rebuildSegments()` yanks the segments; the in-flight glass frames
freeze composited (same family as flutter/flutter#189373's stale-frame
re-present; the lens is a private portal-view — no published invalidation
hook). Ecosystem check (docs/research/ios26-segmented-lens-*.md): full
recreation is the converged cure (expo#43743 "until remounted",
RN-screens#4081 detach/reattach, SO 79739688 `.id(glassNonce)`, and the
upstream package itself normalizes destroy/recreate for iOS 26 glass);
nothing lighter has a confirmed win.

Round 6:

- `CupertinoSegmentedControlPlatformView.setBrightness` — **full
  `UISegmentedControl` replacement** (`replaceControlForThemeFlip`):
  content rebuilt from fields via `rebuildSegments()`, selection/tint/
  enabled/alpha/interaction captured from the old control, target re-wired,
  edge pins re-created — all inside `applyInstantly`, so the fresh lens
  rests on the selection with no in-flight frames to freeze.
- Uniformity audit (subagent, full table in the session log) found the
  remaining explicit-glass classes with consumers but only trait pins:
  **CNSearchBar and CNTextField** (SwiftUI `.glassEffect` capsules). Both
  hold user state in the view (`@State` search text, focus), so a re-root
  was out; instead a shared `CNAppearanceEpoch` (Utils/CNAppearance.swift)
  is bumped in their `setBrightness` (now wrapped in `applyInstantly`) and
  hung via `.id(epoch)` on ONLY the `glassBackground` subtree — the glass
  is destroyed + recreated while the field's state diffs clean.

Watch-list (measured fine in every clip so far — escalate only if a clip
catches one stale): CNSlider / CNRangeSlider / CNSwitch (system glass,
trait pin suffices — no config baking), CNButton SwiftUI tier +
CNFloatingIsland + CNNativeTabBar + CNSearchScaffold + orphaned
CupertinoTabBarSearchView + experimental CNGlassCard (no showcase
consumer), `native_tab_bar.dart` manual-only sync (:209). The transient
dark "…" mid-tab-swipe at 2.3s in this clip is the pressed state, not a
theme leak.

**Status: awaiting the next device clip.** Watch: segmented lens through
several rapid flips (expected: pill rests cleanly on the selection each
time), search bar + text field capsules on the Search/Notes tabs, and
confirm FAB/"…"/tab bar/Send stay perfect.

## 16. The 10-40 clip — lag is done; the popup chrome is one presentation behind

Verdict on round 6 from the 10-40 device clip: **every glass control now
flips on-frame** — FAB, "…", tab bar, Send pill, segmented (clean pill, no
lens smears), cards, icon rows. The remaining defect is not lag but the
**popup chrome's theme**: with the app dark the FAB/"…" menus render LIGHT
(5.7s, 8.5s); with the app light they render DARK (19.8s, 22.7s) — always
exactly one presentation behind, while the Send pill's menu followed the
app theme both directions (11.3s dark, 22.7s light). First presentations
fall back to the OS/init traits. Pattern: each UIKit menu presentation
reuses the environment captured at the PREVIOUS presentation —
FB13391355-class; no public lever reaches that cache (window-pinning
hypothesis checked and eliminated — nothing in the app or vendor tree
touches `window.overrideUserInterfaceStyle`).

The fix is the user's call, literally: make the FAB/"…" popups the Send
pill's solution. `CNPopupMenuButton.build` now reroutes group-compatible
glass icon triggers to a **one-button `CNGlassButtonGroup`** with a single
`CNButtonData.popup` segment — the exact SwiftUI `Menu` construction whose
chrome resolves `.environment(\.colorScheme)` fresh per presentation.
Mapping: trigger icon/imageAsset/customIcon, items label+symbol-name+
custom-icon+destructive, tint, and circle sizing via
`minHeight: diameter` + symmetric padding (the group has no width key).
Guard `_canUseGlassGroupTrigger` keeps the UIKit path (with the caveat)
for label triggers, prominentGlass, dividers, checked/disabled items,
per-item tints/assets, preserveTopToBottomOrder.

Tests: `test/popup_menu_glass_reroute_test.dart` — red-then-green (route
test fails pre-reroute; divider guard is the invariant), vendor suite
128 green; showcase 128 + ui_library 312 green; iOS build clean.

Watch-list for the next clip: menu item glyphs render at the group's
system default size (the name-only mapping drops per-item symbol sizes —
visually indistinguishable in the Send menu); the FAB/`…` triggers are now
SwiftUI glass capsules like the toolbar's — check diameter parity (44/56)
and that the menus anchor like before. CNPopupMenuButton's UIKit path
remains for the guarded cases — its chrome caveat is now documented here
rather than fixed.

## 17. The 11-09 clip — popup-close materialise flash

The 11-09 clip (round-7 binary): popup chrome follows the app theme both
directions now — the reroute worked. Remaining defect: on popup CLOSE the
trigger re-appears with the wrong color before settling — Send chevron
half gray (light mode, 1.7s), whole Send pill a muddy gradient (dark mode,
12.3s), FAB a solid black opaque circle for ~1s (15.8s → restored 16.8s).
Cause: dismissing the `Menu` re-establishes the trigger's glass, and the
DEFAULT `.glassEffectTransition` replays the materialise animation (the
same "glass materialises with a fade" Apple's WWDC25-284 demos for first
appearance — and expo#44126's lingering post-dismiss artifact family).

Fix (one line, uniform): `.glassEffectTransition(.identity)` inside
`applyConditionalGlassEffect` (GlassButtonSwiftUI.swift) — the single
choke point for every group button's glass, so it covers the Send split
(union drags the action half into the same re-materialise), the FAB and
"…" (one-button groups since §16), and the toolbar. Identity snaps the
glass to its final state instead of fading through the muddy intermediate.
`LiquidGlassContainerView` already made this choice for the same artifact
class (:321-322). Trade-off, accepted: first-appearance materialise for
group buttons is gone (route entrances are owned by the chrome gate /
transition containment idioms anyway).

Build + vendor 128 + showcase 128 green. **Status: awaiting the device
clip.** Watch: open/close each popup in both modes — the trigger should be
visually continuous through the close, no flash; and confirm the open
morph still reads well with the transition at identity.

## 18. The 11-22 clip — transition theory falsified; the real lever is re-composite

The 11-22 clip (round-8 binary): **nothing changed** — all three popup
triggers (Send pill ~2.8–3.6s, FAB ~5.9–6.5s, `…` ~8.0–8.8s) still flash
on menu close. Full-res frame crops characterize the artifact precisely:
the trigger's own shape (whole unioned pill for Send, circle for FAB/`…`)
rendered FLAT SOLID black (dark mode) for ~0.7–1s, then self-healing with
no interaction. §17's hypothesis (default materialise transition) is
thereby falsified *in-path* — the edit was confirmed live in both glass
call sites (`GlassButtonSwiftUI.applyConditionalGlassEffect` and the
hoisted Menu chain in `GlassButtonGroupView.buttonView`).

Root cause (researched, sources in `docs/research/`): **known Apple bug,
unfixed through iOS 26.4** — Apple forums thread 826863 ("SwiftUI Liquid
Glass Menu briefly turns black after dismissing"), expo#43953 ("glass
material briefly becomes fully opaque ~1 second after the menu is
dismissed… fails to re-composite"), expo#44126 (pure-SwiftUI repro,
`_UIReparentingView` console warning). Mechanism: the system morphs the
trigger's glass into the presented menu (WWDC25-284: "glass buttons morph
into overlays") by reparenting its rendering into the presentation
hierarchy; on dismiss the re-attached glass re-composites its backdrop
sampling **asynchronously (~0.5–1s)**, drawing the fallback material
(solid black dark / muddy gray light — exactly the observed fill) in the
interim. `.glassEffectTransition` only governs SwiftUI-driven
insertion/removal inside OUR `GlassEffectContainer`; the morph never
passes through it — hence round 8's no-op. (The modifier stays, with a
corrected comment: it still covers engine platform-view detach/reattach,
the `LiquidGlassContainerView:305-322` rationale.)

Cure (this round): **piggyback the theme-lag lever on a dismiss
detector.** `GlassButtonGroupPlatformView` observes
`UIWindow.didBecomeKeyNotification`; when OUR window re-becomes key (a
presentation over us just closed — fires for item selection AND
tap-outside; the menu window's own didBecomeKey on present is filtered by
an identity check against `container.window`), groups containing a popup
trigger replay `applyBrightness` — epoch bump + re-root = fresh layers
that composite AND sample the same frame, the device-proven cure for
unsampled glass. Idempotent, so spurious fires (keyboard hide) are
no-ops; only popup-hosting groups replay. Detection rationale: SwiftUI
`Menu` exposes no dismiss callback and tap-outside reaches neither Dart
nor the hosting view, so the window-key change is the only public signal
that covers both dismiss paths.

Community alternatives, ranked by the research, and why not chosen:
`.buttonStyle(.glass)` on the Menu (expo-maintainer-endorsed, one
user-confirmed) — replaces our custom glass chain, risks the Send pill's
union merge and the 44/56pt geometry the clips validated; kept as the
fallback if this round fails on device. Toolbar placement (avoids the
reparenting path) — inapplicable to in-content FAB/pill. `.clipped()` /
clipShape — masks the rectangular-halo variant, not a trigger-shaped
fill. UIKit `showsMenuAsPrimaryAction` — no reports of THIS flash, but
carries the one-presentation-behind chrome bug (§16) and its own glass
flicker catalog; its close behavior stays unverified. No public API
presents a SwiftUI Menu without the morph (confirmed across docs).

Build clean (29.4s); vendor 128 + showcase 128 green. **Status: awaiting
the device clip.** Watch: open/close each popup both modes — trigger
should be sampled glass the frame the chrome finishes collapsing; check
the close morph doesn't glitch from the mid-flight re-root (if it does,
the next iteration delays the replay ~0.3s); keyboard show/hide near the
groups should cause no visible change.

## 19. The 11-46 clip — replay inert too; the cure is `.buttonStyle(.glass)`

The 11-46 clip (round-9 binary): flash unchanged on all three triggers
(Send pill solid ~4.8–6.5s, FAB solid at 8.5s, `…` solid at 12.7s).
Either the iOS 26 menu presentation never makes its window key (so
`didBecomeKeyNotification` never fired — plausible: `_UIReparentingView`
presents inside the existing hierarchy), or the replay fired and even a
fresh re-root cannot beat the system's async re-sample. Indistinguishable
without device logs and not worth instrumenting: that is **two failed
post-hoc cures** (rounds 8 + 9), which falsifies the shared assumption —
"keep our custom `.glassEffect()` chain and fix the flash after dismiss."
The artifact lives entirely inside the system's morph/reparenting
machinery; the only confirmed lever is to stop handing it a custom glass
label to reparent.

Fix (round 10): popup triggers in `GlassButtonGroupView.buttonView` now
render their glass via **`.buttonStyle(.glass)` on the Menu** — the expo
maintainer-endorsed, reporter-confirmed workaround (expo#43953 comment,
docs PR #44131). The system's own glass control rendering is one the
morph hands back correctly. The round-9 observer machinery is deleted
(dead weight), and `.glassEffectTransition(.identity)` stays ONLY for
its real scope (SwiftUI/engine add-remove), with comments corrected.
Union/id modifiers are still applied to the Menu — whether
`glassEffectUnion` associates with style-rendered glass is unverified;
if the Send split pill shows a seam in the next clip, the container's
proximity merge (spacingForGlass 80) is the fallback. Inner Button keeps
`NoHighlightButtonStyle`, which overrides the inherited `.glass` style
(explicit style beats environment). Costs accepted: popup triggers lose
the custom shape/transition chain (all capsule/circle anyway) and any
per-trigger `borderRadius` override.

Build clean (23.0s); vendor 128 + showcase 128 green. **Status: awaiting
the device clip.** Watch: (1) close each popup both modes — trigger
should be continuous glass through the close, no solid flash; (2) the
Send pill should still read as ONE unioned pill, halves unseamed;
(3) trigger geometry (44pt pill, 56pt FAB circle) — the style hugs the
padded label, so diameters should hold; (4) open morph should be
unchanged. If the flash STILL shows: that is strike three — stop
patching; the remaining options are the masked variants (clipShape) or
accepting the artifact until Apple fixes it, and that call belongs to
the user.

## 20. The 12-00 clip — flash cured; triggers bare (borderless conflict)

The 12-00 clip (round-10 binary): **the close flash is GONE** on all
three triggers — the `.buttonStyle(.glass)` cure works. But the triggers
lost their glass entirely: `+`/`…`/chevron render as bare glyphs; the
Send action half (its own `.glassEffect()`, untouched) still has glass
but reads thinner alone, the one-pill union look gone. Full-res crops
confirm: no capsule at all around popup triggers.

Cause: **`.menuStyle(.borderlessButton)`** — kept from the pre-round-10
construction, where it suppressed the default chrome because WE supplied
the glass. It also suppresses the chrome `.buttonStyle(.glass)` renders,
so the style had nothing to draw. Fix (round 11): delete the menuStyle
line; the default menu style lets the button style draw the trigger.

Build clean (23.3s); vendor 128 + showcase 128 green. **Status: awaiting
the device clip.** Watch: (1) triggers glass again (56pt FAB circle,
44pt pill, `…` circle); (2) close still flash-free — both properties
must hold together this time; (3) Send pill: does the style-rendered
chevron glass merge with the action half (union or container proximity,
spacing 8 < 80)? If a seam persists, that is the next and only remaining
defect; (4) trigger sizing — the style may add its own internal padding.

## 21. The 12-12 clip — glass back, flash-free; triggers oversized ellipses

The 12-12 clip (round-11 verdict): **glass restored on all three popup
triggers and the close stays flash-free in both modes** — the round-10
cure and round-11 un-suppression hold together. Remaining defect:
geometry. The `…` trigger renders ~72×52pt (target 44 circle), the FAB
~85×73pt (target 56 circle) — wide ellipses, visibly wrong next to the
44pt custom-glass circles beside them.

Cause: **double padding**. `_buildAsGlassGroup` sent
`padding: (diameter-iconSize)/2` + `minHeight: diameter`, so the Menu's
label (the full `GlassButtonSwiftUI`) was already a `diameter`² box —
then `.buttonStyle(.glass)` added its OWN internal label padding, and
the chrome follows the label's aspect (wide ellipsis glyph → ellipse).

Fix (round 12), measured not guessed — an iOS 26.5 simulator probe gave
a local loop (geometry is sim-accurate; glass compositing is not, but
that is not what was being measured):

1. The popup label is now a bare glyph centered in a clear square box of
   side `minHeight − 2·glassPad` (`popupTriggerLabel` in
   `GlassButtonGroupView.swift`); the old Dart-side padding is deleted.
2. `.buttonBorderShape(.circle)` forces circular chrome regardless of
   glyph aspect (all group-routed popups are icon-only —
   `_canUseGlassGroupTrigger`).
3. An outer `.frame` on the Menu does NOT constrain the style chrome
   (tried, inert) — the style measures only the label's bounds.
4. `glassPad = 7`pt/side, calibrated against the known-good 44pt
   custom-glass search circle via exact pixel-edge scans (script, not
   eyeball): menu 36→**44.0pt exact**, FAB 48→58.3pt measured at the
   shadow rim (glass body on target), Send pill uniform **44pt** and
   unseamed. kimitail: if Apple retunes the style padding, the diameter
   drifts a couple of pt; the chrome stays circular.

Dead code removed with it: the popup-only `onPressed: {}` /
`applyOwnGlass: !button.isPopup` branches (the popup label is no longer
a `GlassButtonSwiftUI` at all).

Sim-verified screenshots: `/tmp/glass-r12/sim-after3.png`. Device build
clean (153.6s); vendor 128 + showcase 128 green. **Status: awaiting the
device clip.** Watch: (1) `…` == search circle diameter, FAB == 56pt
circle, Send pill one unseamed 44pt pill; (2) close still flash-free
with the new label (the cure mechanism — system-rendered chrome — is
unchanged, but confirm); (3) popup open morph and menu items unchanged.

## 22. User decision — revert the popup triggers to the round-9 construction

Rounds 10–12 proved the `.buttonStyle(.glass)` cure works for the
popup-close flash, but its chrome sizes itself from the label with
undocumented internal padding (§21): exact 44/56pt geometry only via a
measured-constant clear-box label + `.buttonBorderShape(.circle)` — a
compensation stack, not native behavior, and still ±2pt off the
custom-glass circles beside it. User call: **"not really native — revert
to round 9."**

Reverted: the popup branch of `GlassButtonGroupView.buttonView` is the
round-9 construction again — `baseButton` (full `GlassButtonSwiftUI`,
`applyOwnGlass: false` for popups) as the Menu's label,
`.menuStyle(.borderlessButton)`, and the custom glass hoisted onto the
Menu via `applyConditionalGlassEffect` (regular glass, capsule or
config-borderRadius shape, union/id intact). The Dart side restored with
it: `_buildAsGlassGroup` sends `padding: (diameter-iconSize)/2` +
`minHeight: diameter` so the padded label IS the diameter.

Accepted known issue (user's call, documented so nobody re-attempts
blindly): the popup-CLOSE flash returns — Apple bug (forums 826863,
expo#43953/#44126, unfixed through iOS 26.4): the dismiss morph
reparents the custom glass and re-composites its backdrop sampling
~0.5–1s late. Post-hoc cures were falsified in rounds 8–9; the
system-style cure in rounds 10–12. The remaining untried levers, if the
flash ever becomes worth another round: toolbar placement (inapplicable
to in-content FAB/pill), or masking via clipShape (masks the halo
variant, not a trigger-shaped fill). Most likely true fix: an iOS 26.x
update from Apple.

Sim-verified (iOS 26.5): menu trigger 44.0pt exact, Send pill uniform
44pt, FAB circle at 56pt body. Device build clean (150.1s); vendor 128 +
showcase 128 green. **Status: awaiting the device clip** to confirm the
restored look (correct circles/pill, flash present and accepted).

## 23. The 14-01 clip — round-9 look confirmed; rapid flips strand views; the settle replay

The 14-01 clip (round-13 revert binary): slow flips are perfect
everywhere — `…` 44pt circle, FAB 56pt circle, Send pill one unioned
44pt pill, icon rows exact. The round-9 construction is the right look.
Residual defect: on RAPID successive flips individual widgets get
stranded on the previous theme for seconds — the `!` icon solid white
through dark mode (7.5s–11.3s), the `i` icon solid dark in light mode
(15.0s, self-healed by 18.8s with no new flip), and mid-flip frames show
Flutter cards already flipped while native glass lags (~0.5s, the known
re-root cost).

Mechanism: the per-flip apply (trait override + config teardown +
re-attach, or epoch + re-root) is a multi-step mutation; under a flip
storm the render server coalesces, and a view mid-mutation when the next
flip lands completes with the PREVIOUS flip's appearance — then waits
for an incidental re-composite (self-heal, seconds) or the next flip
(stuck). The Dart fan-out is ordered per channel and not at fault.

Fix (round 14): `CNAppearanceSettleReplay` (Utils/CNAppearance.swift) —
a generation-guarded delayed replay. Every `setBrightness` handler now
ends with `settleReplay.poke { self?.applyBrightness(isDark) }`: 0.35s
after the LAST flip (superseded generations never fire), the final apply
replays once, so the end state is deterministic regardless of mid-storm
coalescing. The single-flip fast path is untouched. Swept across ALL 15
native view types (group, CNButton, icon, sliders, switch, segmented,
both tab bars, search bar/scaffold/tab-search, text field, popup-UIKit,
floating island) — 13 of them by a delegated sweep using the two
hand-built exemplars; all 15 files grep-audited (property + poke), two
spot-checked line by line (CNNativeTabBar static-channel shape, switch
extract shape). kimitail: the 0.35s delay is a heuristic — long enough
to outlast a storm, short enough to usually beat a finger moving to a
popup trigger (a group re-root mid-presentation remains untested).

Durability docs (the "always deliver liquid glass correctly" contract):
the mechanics + this sweep are now written into
`skills/appbox-builder/SKILL.md` ("Native liquid glass (iOS 26) —
settled mechanics"), `skills/appbox-scaffolder/SKILL.md` (kind
resolution carries the mechanics by construction), and the vendored
package's own `AGENTS.md` (a 4-point checklist any NEW native view type
must implement). Scaffolded apps get correct glass by composing kit
wrappers — no per-app work, no hand-rolled platform views.

Sim + device builds clean; vendor 128 + showcase 128 green. **Status:
awaiting the device clip.** Watch: rapid Auto/Light/Dark mashing — no
widget may remain on the wrong theme >0.5s after the last tap; popup
open within ~0.5s of a flip (the untested re-root-mid-presentation edge);
everything else unchanged.

## §24 — Final sweep, docs verification, deterministic guard (2026-08-12)

User verdict on round 14: works ("awesome"). Final audit before commit:

- **Full wiring audit, both tiers.** Native: all 15 brightness-handling
  Swift views carry scoped `overrideUserInterfaceStyle` + the
  `CNAppearanceSettleReplay` property/poke pair; the six pure-override
  handlers (CNNativeTabBar, search scaffold/tab-search, switch, both
  sliders) deliberately skip `applyInstantly` — a bare override assignment
  does not re-establish glass and was measured the fastest restyle on
  device, so wrapping it would be ceremony (kimitail: uniformity of the
  CURE, not of the code shape). Dart: every platform-view component pushes
  brightness (9 direct `setBrightness`, 5 `_syncBrightnessIfNeeded`,
  container via `updateConfig`); split_button/bottom_sheet/toast/
  popup_gesture/async_resolution_state are pure-Dart compositions that
  inherit brightness from their child — exempt, verified no channel.
- **Gap found and closed:** `LiquidGlassContainerView` (the glass cards)
  had `applyInstantly` + re-root but no settle replay — its flip path is
  `updateConfig`, not `setBrightness`. Added `settleReplay.poke {
  self?.updateConfig(args: args) }` (replays the final config verbatim).
- **Apple-docs verification** (read-the-damn-docs, agent-20):
  `UIView.overrideUserInterfaceStyle` documented as not crossing into
  embedded child VCs — applying it to BOTH container and hosting
  controller is exactly what the docs imply is required;
  `glassEffectID`/`glassEffectUnion` confirmed as the real iOS 26 union
  APIs; the popup-dismiss flash is confirmed on Apple forums thread
  826863 (reproduced on iOS 26.3) with NO fix listed in the 26.4 release
  notes — accepting it remains correct.
- **Deterministic guard:** `tool/check_theme_wiring.sh` in the vendored
  package fails if any brightness-handling Swift view is under-wired, a
  banned pattern (`window.overrideUserInterfaceStyle`,
  `.preferredColorScheme(`) reappears outside comments, or a Dart
  platform-view wrapper stops pushing brightness. Referenced from the
  vendored `AGENTS.md` checklist (point 5) and both skill files.

**Status: committed.** Whole saga changeset (rounds 1–14 + this sweep)
lands as one commit; `t3ci/` and `tools/watch_device.sh` left untracked
(not part of this work).
