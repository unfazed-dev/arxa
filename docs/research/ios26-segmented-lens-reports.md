# iOS 26 UISegmentedControl glass-lens smear — third-party report sweep

Date: 2026-08-12. Method: WebSearch + FetchURL only. A report is "verified" only if
the URL was actually fetched and the content was on-topic. Search-snippet-only items
are quarantined under **Unverified leads**.

Target bug class: on iOS 26 (Liquid Glass), the `UISegmentedControl` sliding glass
"lens" leaves frozen semi-transparent smears on segments it passed over when an
in-app light/dark flip (`overrideUserInterfaceStyle` + segment rebuild inside a
no-animation `CATransaction`) lands mid-slide. Cleared by scroll / next flip /
recreating the view.

## Exact matches (lens smears/trails on segmented control)

**None verified.** No fetched page describes smear/trail/ghost residue of the sliding
lens after an appearance flip. The closest in class is the "glass handle freezes
mid-air" report (both Stack Overflow and Apple Developer Forums), which is a
stuck/frozen glass lens on a stock UIKit `UISegmentedControl` — but both URLs are
bot-walled for this fetcher, so it sits under Unverified leads despite strong,
multiply-corroborated snippet evidence. It confirms Apple ships a lens that *can*
wedge visually, but it is a drag-to-disabled-segment freeze, not an
appearance-change smear.

## Adjacent reports (segmented control / iOS 26 rendering-state bugs, no smears)

All fetched and confirmed.

- **react-native-screens #4081 — "[iOS 26] Stack header Liquid Glass blur lost in
  inactive tabs after Appearance.setColorScheme"** (2026-05-21)
  https://github.com/software-mansion/react-native-screens/issues/4081
  The *appearance-flip* scenario closest to ours: calling
  `Appearance.setColorScheme(...)` while a tab is inactive permanently breaks that
  tab's Liquid Glass nav-bar blur until a full detach/reattach. > "The affected nav
  bar stays broken across all pushed screens within that stack until the user leaves
  the tab and re-enters." Confirms UIKit glass surfaces cache appearance-resolved
  state and fail to invalidate it on an off-screen trait change; recreation cures it
  — same shape as our workaround.

- **expo/expo #44739 — "[iOS 26][expo-ui] Picker with pickerStyle('segmented')
  missing Liquid Glass styling"** (2026-04-13)
  https://github.com/expo/expo/issues/44739
  Segmented picker on iOS 26 physical device renders with the pre-26 outlined style;
  slide animation works but the glass pill never appears. Suspected hosting-layer
  propagation failure. > "The selection slide animation works on tap, but the glass
  material and translucent pill appearance are missing."

- **dotnet/maui #34143 — "[iOS] Tab bar ghosting issue on iOS 26 (liquid glass)"**
  (2026-02-19)
  https://github.com/dotnet/maui/issues/34143
  After a modal-then-tab navigation on iOS 26, the native tab bar renders with the
  selected item emptied and visible ghosting; fixed only by
  `UIDesignRequiresCompatibility=YES` or avoiding the modal stack.
  > "The selected tab bar item becomes empty. Ghosting issue appears."

- **Plugin.SegmentedControl.Maui #38 — "[Bug] SegmentedControl Invisible in
  Shell.TitleView on iOS 26 (Liquid Glass Rendering Issue)"** (2025-10-19)
  https://github.com/thomasgalliker/Plugin.SegmentedControl.Maui/issues/38
  `UISegmentedControl` in a nav-bar TitleView allocates space but never renders on
  physical iOS 26 hardware (simulator differs). > "This suggests a deep issue with
  the native hardware rendering pipeline on iOS 26."

- **DevelopersIO (JP, English version) — "Xcode 26 + UIDesignRequiresCompatibility
  environment has an issue with misaligned tap positions on UISegmentedControl"**
  (2026-01-22, Japanese dev blog)
  https://dev.classmethod.jp/en/articles/xcode26-uisegmentedcontrol-tap-position-bug/
  Tapping the rightmost segment selects the leftmost when segments were added
  dynamically via `removeAllSegments()` + `insertSegment` under compatibility mode —
  i.e. **the same removeAll/re-insert dance our flip path uses** desyncs UIKit's
  internal segment bookkeeping on iOS 26. Reported to Apple: **FB21712773**,
  forums thread 813511. > "The issue does not occur with statically configured
  segments in Storyboard, but only when segments are added dynamically."

- **flutter/flutter #189373 — "[iOS] FlutterMetalLayer re-presents stale frames:
  transitions visibly run backwards"** (2026-07-13)
  https://github.com/flutter/flutter/issues/189373
  On iOS 26 (physical device), already-displayed frames are re-presented out of
  order — compositor-level stale-frame re-presentation on iOS 26, not UIKit, but the
  same "composited frames never invalidated" family our smears look like.
  > "The display alternates between two frames that were both already shown."

## General Liquid Glass compositing artifacts (other controls)

All fetched and confirmed.

- **MacRumors Forums — "iOS 26 visual glitch megathread"** (2025-12-12, active
  through 2026-03)
  https://forums.macrumors.com/threads/ios-26-visual-glitch-megathread.2474573/
  Catalog of iOS 26 glass rendering bugs, several in the stuck-highlight /
  never-invalidated family: > "Edge highlight animation doesn't reset itself
  properly … it stays stuck until you force your device to move again"; text
  "glitches through" search fields; a white flash on the mini player; and
  **FB21067417** ("Long-Press/Ellipsis Button Visual Artifact", submitted
  2025-11-17) — a circular artifact left after dismissing liquidy popups when
  cross-fade transitions are enabled.

- **callstack/liquid-glass #33 — "LiquidGlassView effect missing or inconsistent on
  physical device (Release build)"** (2025-11-26)
  https://github.com/callstack/liquid-glass/issues/33
  Glass container renders in simulator but the effect is missing or "disappears
  intermittently" on an iOS 26 physical device in Release builds.

## Empty venues

- **Reddit (r/iOSProgramming et al.)** — nothing on-topic. Queries tried:
  "reddit iOSProgramming UISegmentedControl iOS 26 bug selection indicator",
  "site:reddit.com iOS 26 segmented control glass glitch developer" (one query
  failed with a search-backend 500 and was retried in reworded form).
- **Telegram-iOS/Telegram-iOS** — no matching issues. Only press coverage of
  Telegram's *own* liquid-glass-like redesign (WebProNews, Mac Observer), not iOS 26
  native-control bug reports.
- **flutter/packages** — nothing surfaced for segmented control / iOS 26 artifacts.
  (flutter/flutter itself has no CupertinoSegmentedControl liquid-glass artifact
  issue; the team has publicly declined Liquid Glass Cupertino support — see
  flutter/flutter#170310, not fetched, mentioned in press coverage only.)
- **OpenRadar / mirrors** — nothing for this bug class; the lionheart/openradar-mirror
  UISegmentedControl hits are pre-iOS-13-era.
- **Korean / Chinese dev blogs** — Korean queries returned only design-kit news and
  WWDC25 adaptation guides; Chinese (CSDN, juejin, cnblogs) returned iOS 26
  adaptation how-tos (incl. custom glass tab bars using `UIGlassEffect`), no
  lens-smear bug reports. Japanese blogs produced the one solid hit (DevelopersIO,
  above).
- **Apple Developer Forums (direct)** — *unverifiable, not empty.* Every direct
  fetch (threads 789898, 789463, 794234 and multiple tag pages, on both
  developer.apple.com and origin-devforums.apple.com) hit a "Security Verification"
  wall. Snippet evidence (below) shows the venue is in fact rich for this bug class.

## Unverified leads (snippet evidence only — fetch blocked or not attempted)

- **Stack Overflow 79877797 — "Liquid glass segmented control freezes when dragging
  handle to a disabled segment"** (closest in class; SO returns 403 to this fetcher,
  stackprinter mirror unreachable, archive.org rate-limited 429)
  https://stackoverflow.com/questions/79877797/liquid-glass-segmented-control-freezes-when-dragging-handle-to-a-disabled-segmen
  Snippet: > "When I drag the liquid glass handle of the segment view from what was
  previously selected to the disabled segment, the liquid glass handle freezes
  mid-air. … I'm using UIKit, and no extra customizations are applied."
- **Apple Developer Forums cross-post of the same report** (Jan '26, visible
  verbatim in snippets of multiple fetched-via-search tag pages: tags/uikit,
  tags/ios, tags/simulator) — same "freezes mid-air" text with full repro code
  (`removeAllSegments()` + `insertSegment`). Direct fetch blocked by security wall.
- **Stack Overflow 79826825 — "Segmented control has design bugs in Navigation Bar
  with Liquid Glass"** (asked ~2025-12, 818 views; 403 on fetch)
  https://stackoverflow.com/questions/79826825/segmented-control-has-design-bugs-in-navigation-bar-with-liquid-glass
  Snippet: > "When I put a SwifUI segmented control in a navigation bar, liquid
  glass seems to be …" (truncated).
- **Apple Dev Forums 789898 — "UISegmentedControl Not Switching Segments on iOS
  Beta 26"** (2025-08-13) https://developer.apple.com/forums/thread/789898 —
  security wall. Snippet: native UISegmentedControl fails to switch on iOS 26 beta.
- **Apple Dev Forums 789463 — "Xcode 26 Beta1 UISegmentedControl can't change
  value"** (2025-06-25) https://developer.apple.com/forums/thread/789463 — wall.
  Snippet: > "Can't change segment value when tap segment. And selected segment
  title always is white."
- **Apple Dev Forums 794234 — "iOS 26 UISplitViewController in dark mode
  appearance"** (2025-08-12) https://origin-devforums.apple.com/forums/thread/794234
  — wall. Snippet: > "When switching to dark mode, the color of all subviews … of
  the Sidebar [are wrong]." Appearance-switch rendering bug, same family.
- **Apple Dev Forums (title from tag-page snippet) — "iOS 26, UISegmentedControl as
  UIBarButtonItem not respecting selectedSegmentTintColor"** (Aug '25) — wall.
- **Apple Dev Forums UIKit topic snippet — "dark mode on iOS 26 beta 3. All system
  colors are displayed incorrectly …"** (with a `UISegmentedControl` as
  `navigationItem.titleView` in the same post) — wall.
- **react/react-native #57299 — "iOS 26: default contentInsetAdjustmentBehavior
  should be scrollableAxes for liquid glass"** (2026-06-21)
  https://github.com/react/react-native/issues/57299 — snippet only; layout/glass
  interaction, marginal relevance.
- **liquid_glass_widgets changelog "double highlight" mention** — checked:
  https://github.com/sdegenaar/liquid_glass_widgets/blob/main/CHANGELOG.md refers to
  the package's *own* Flutter indicator pill ("This caused the pill to drift out of
  alignment and sometimes produce a 'double highlight' effect"), not an Apple
  control bug. Not a third-party confirmation; noted to avoid a false positive.
  (The pub.dev 0.24.0 changelog page was fetched in full to confirm context.)

## Bottom line

No published third-party report of the *exact* smear-after-appearance-flip signature
was found in any fetchable venue. But the surrounding bug class is well confirmed:
(iOS 26 glass surfaces failing to invalidate after appearance changes — RN screens
#4081), (dynamic `removeAllSegments`/`insertSegment` desyncing iOS 26 segmented
controls — DevelopersIO/FB21712773), (iOS 26 compositor re-presenting stale frames —
flutter/flutter#189373), and (a stock UIKit glass lens that can freeze mid-drag —
SO 79877797 / Apple forums, unverified). "Recreate the native view" being the
reliable cure matches the recovery pattern in the RN-screens report.
