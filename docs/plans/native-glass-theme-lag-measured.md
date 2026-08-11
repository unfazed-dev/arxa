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

## 7. B2 — open, with the instrumentation to close it

Not determined. Candidates surviving the evidence:

1. UIKit coalescing the trait change to a later layout/update pass, which for a
   Flutter platform view is scheduled by Flutter, not by UIKit.
2. Render-server serialisation of glass re-rasterisation across N views
   (7 views × ~300 ms ≈ the 2.1 s total span).

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
