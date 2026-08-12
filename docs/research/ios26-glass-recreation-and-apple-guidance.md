# iOS 26 Liquid Glass — recreation-as-workaround evidence + Apple guidance

Research date: 2026-08-12. Everything below was actually fetched and read; anything I
could not fetch is in the last section. Context: Flutter app embeds a native
`UISegmentedControl` via hybrid platform view; app flips light/dark via per-view
`overrideUserInterfaceStyle`; after each flip the sliding glass "lens" leaves frozen
semi-transparent smears; only fully recreating the native view cures it.

---

## 1. Recreation-as-workaround evidence

Verdict up front: **yes — recreating (or forcing a re-render / re-application of the
glass effect) after an appearance change is a repeatedly reported and shipped
workaround across the ecosystem.** The closest matches to our exact scenario
(appearance flip → stale glass rendering, cured only by full recreation):

### 1.1 Stack Overflow — recreation via forced redraw is the accepted answer

- https://stackoverflow.com/questions/79739688/liquid-glass-not-appearing-for-the-first-launch-of-the-app
- Question: glass missing on first launch until app is backgrounded/foregrounded.
  Accepted answer: *"It seems that on first launch the system doesn't fully initialise
  the liquid glass shared background. When you navigate away and back it gets rebuilt
  and is then applied properly.… On your `TabView`, attach an `.id` and increment it
  inside `.onAppear`. This forces the TabView to very quickly redraw, resulting in the
  glass showing immediately."* (`.id` bump = destroy + recreate the native view.)
- Critically, a commenter ties it to our exact lever: *"I also noticed that the issue
  might be related to setting the `overrideUserInterfaceStyle` on the app's window… We
  support option to override the system theme so we need to support it and it was
  causing the issue after all."* Another commenter confirms the `.id` recreation fix
  worked but needed a `UUID` instead of an int.

### 1.2 expo/expo #43743 — root-cause writeup: UIGlassEffect ignores trait changes; "stays until remounted"

- https://github.com/expo/expo/issues/43743
- *"`GlassView`'s `colorScheme` prop correctly sets `overrideUserInterfaceStyle` on the
  native view, but the `UIGlassEffect` visual appearance doesn't update… glass material
  stays in dark appearance **until the component is remounted**."*
- Root cause stated plainly: *"Changing `overrideUserInterfaceStyle` updates the view's
  trait collection, but `UIGlassEffect` (iOS 26) doesn't automatically re-render its
  visual appearance in response to trait collection changes. The effect needs to be
  re-applied via `glassEffectView.effect = effect`."* Also notes the window-level path:
  *"React Native sets `overrideUserInterfaceStyle` on all windows… `UIGlassEffect`
  still needs re-application."*
- Note the nuance: for a **custom `UIVisualEffectView + UIGlassEffect`** the partial
  lever (re-assign `.effect`) was sufficient — but that lever does not exist for a
  closed control like `UISegmentedControl` whose lens is private. Consistent with our
  finding that partial levers fail there.

### 1.3 expo/expo #43732 — "Liquid Glass can't recover" after appearance toggle

- https://github.com/expo/expo/issues/43732
- *"Toggle appearance and change to another tab. Liquid Glass can't recover and
  disappears. If you toggle again it returns."* (iOS 26.2, Expo 55.) Same symptom
  family: appearance flip leaves glass in a broken state; only a later structural
  change restores it.

### 1.4 react-native-screens #4081 — glass blur lost on inactive tabs; cured by detach/reattach

- https://github.com/software-mansion/react-native-screens/issues/4081
- *"On iOS 26 with native Liquid Glass nav bar, calling `Appearance.setColorScheme(...)`
  from JS while a tab is inactive breaks the scroll-edge blur transition on that tab's
  navigation bar.… Switch tab away + back → **full detach/reattach cycle → blur
  restored**."* Only off-screen (not-in-hierarchy) views break — matches Apple's own
  "views only update traits while in the hierarchy" behavior (§2.5).
- Cross-references #3716 (Tabs `colorScheme` fix, 4.25.0) and expo#43743.

### 1.5 Flutter package cupertino_native_better — destroy/recreate of native platform views as standard iOS 26 glass practice

- https://github.com/gunumdogdu/cupertino_native_better/blob/main/CHANGELOG.md (also
  https://pub.dev/packages/cupertino_native_better/changelog)
- This package embeds native UIKit (UITabBar, **CNSegmentedControl**, buttons, etc.)
  in Flutter platform views — same architecture as ours. Its changelog normalizes
  platform-view destroy/recreate for iOS 26 glass artifacts:
  - 1.5.1 (#53): *"Each widget now destroys its PlatformView (with a same-size
    placeholder reserving the layout slot) while a sheet covers it, and recreates it
    when the sheet dismisses"* — applied to all 9 glass widgets incl.
    `CNSegmentedControl`.
  - 1.4.5 (#41): platform view previously *"destroying the native `UITabBar`. On
    return, a fresh view was created"* (recreate-on-return), later changed to keep the
    view mounted to avoid a *"visible 'platform view recreate + index restore' jump"*.
  - 1.4.2: *"tab bar's selected index resetting to 0 after a modal/sheet closed and
    the platform view was recreated"* — recreation is routine enough that state-restore
    after recreation is its own bug class.
  - 1.4.0 (#29): glass halo *"renders a translucent halo that extends slightly outside
    the view's frame… visible during route transitions"* — same stale-compositing
    family as our smears; mitigated via containment clipping, and by destroy/recreate
    in later releases.
  - 1.4.1 known issue: simulator glass is software-rasterized; artifacts there
    *"do not appear on real iOS 26 devices"* — verify on device.

### 1.6 dotnet/maui #34143 — "Tab bar ghosting issue on iOS 26 (liquid glass)"

- https://github.com/dotnet/maui/issues/34143
- *"The selected tab bar item becomes empty. Ghosting issue appears."* iOS 26, after a
  modal→tabs navigation. Reporter's workarounds: `UIDesignRequiresCompatibility` or
  avoid modal stack — recreation not listed, but "ghosting" = same stale-frame symptom
  class. Repro: https://github.com/oleh-kaliuzhnyi/ShellTabBarGhostingIssue

### 1.7 callstack/liquid-glass — glass disappears on device; props mount-only

- https://github.com/callstack/liquid-glass/issues/33 — *"the glass view either fails
  to render the blur effect entirely or disappears intermittently"* (iPhone 11 Pro,
  iOS 26, Release). No fix in the fetched body.
- https://github.com/callstack/liquid-glass README known issues: *"`interactive` prop
  is not changed dynamically, it is only set on mount"* — the library itself works
  around UIKit glass' reluctance to update in place by treating props as mount-time
  (i.e. change ⇒ new instance).

### 1.8 Apple Developer Forums (inverse data point: recreation *while hidden* triggers bad glass)

- A thread excerpted on the UIKit tag listing
  (https://developer.apple.com/forums/tags/uikit?page=5, also visible on
  ?page=3/4 sortings and the iOS tag page 6) titled "I'm seeing a rendering issue with
  UITabBarController on iOS 26 (Liquid Glass)…" contains: *"// Recreate the tab bar
  while it is still fully hidden by the modal. // This seems to trigger incorrect
  Liquid Glass rendering."* I could not resolve the thread's own URL (tag pages render
  post bodies server-side but my fetch dropped the hrefs) — treat as real but
  second-hand. Lesson if recreation is used: **recreate while visible** (or force a
  layout pass after re-adding), not while covered/hidden.

### 1.9 Does Flutter itself recreate UIKit views on brightness changes? — No evidence

- Fetched `FlutterViewController.mm` (main):
  https://raw.githubusercontent.com/flutter/flutter/main/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm
  In the fetched portion, `viewWillAppear` calls `onUserSettingsChanged:` which
  *"Send[s] platform settings to Flutter, e.g., platform brightness"* over the settings
  channel, and `surfaceUpdated:` recreates the **Flutter surface** on reappearance —
  nothing recreates platform-view UIViews on trait/brightness change. (File fetch
  truncated before the `traitCollectionDidChange` section, so this is "no evidence in
  fetched portion", not proof of absence.)
- flutter/flutter #170310 (https://github.com/flutter/flutter/issues/170310) is the
  Liquid Glass/Cupertino tracker — a "strategic pause" + decoupling announcement; no
  platform-view recreation discussion in the fetched body.

---

## 2. Apple guidance

### 2.1 WWDC session numbers — verified by fetching the session pages

| Session | # | Verified via |
|---|---|---|
| Meet Liquid Glass | **219** | fetched https://developer.apple.com/videos/play/wwdc2025/219/ |
| Build a UIKit app with the new design | **284** | fetched https://developer.apple.com/videos/play/wwdc2025/284/ |
| What's new in UIKit | **243** | fetched https://developer.apple.com/videos/play/wwdc2025/243/ |
| Build an AppKit app with the new design | **310** | locale mirrors fetched in search results, e.g. https://developer.apple.com/br/videos/play/wwdc2025/310/ |
| Get to know the new design system | **356** | search result https://developer.apple.com/videos/play/wwdc2025/356/ |
| Build a SwiftUI app with the new design | **323** | search result https://developer.apple.com/videos/play/wwdc2025/323/ |
| (WWDC23) Unleash the UIKit trait system | **10057** | fetched https://developer.apple.com/videos/play/wwdc2023/10057/ |

### 2.2 WWDC25 284 "Build a UIKit app with the new design" — the on-point one

Fetched full transcript page. Directly relevant moments (timestamped code snippets are
verbatim from the page):

- **20:54 — "Adapting to dark mode"**: Apple demonstrates programmatic per-view
  appearance override **inside an explicit animation block**:
  ```swift
  UIView.animate {
        view.overrideUserInterfaceStyle = .dark
  }
  ```
  So Apple's sanctioned way to flip `overrideUserInterfaceStyle` on a live view is to
  wrap it in `UIView.animate`, not to set it bare.
- **21:30 — "Glass adapts based on its size"**: combines
  `view.overrideUserInterfaceStyle = .light` with bounds changes in one
  `UIView.animate` — appearance flips are meant to be animated alongside layout.
- **20:28** animating `effectView.effect = glassEffect` produces a "materialize"
  animation; **23:20** setting `effect = nil` dematerializes. Re-assigning `.effect` is
  the documented way to make a glass visual-effect view re-render — the exact lever
  expo used (§1.2), unavailable for closed controls.
- **24:33 — "Dividing glass into multiple views"**: splitting one glass element into
  many is done by `UIView.performWithoutAnimation { containerEffectView.contentView.addSubview(view) … }`
  then animating frames — i.e. Apple itself **removes/adds glass subviews to the
  hierarchy** (structural change) for state transitions rather than mutating in place.
- Controls chapter (17:24): *"Those are places where system controls have adopted
  liquid glass… When using Liquid Glass in your UI… limit Liquid Glass to the most
  important elements… use the system views and controls for the best experience."*
  (Nothing on segmented-control lens specifics in the extractable transcript.)
- Nothing in the transcript says "recreate the control on appearance change" — but it
  establishes that (a) appearance flips should be animated, and (b) glass elements are
  expected to be re-materialized / re-parented rather than subtly mutated.

### 2.3 WWDC25 219 "Meet Liquid Glass"

Fetched. Design-principles session: lensing, adaptivity (*"Liquid Glass adapts based on
the content beneath it"*), Regular vs Clear variants, *"avoid putting glass in the
content layer and avoid putting within or on top of other glass elements"*. No
engineering guidance on appearance changes or recreation.

### 2.4 WWDC25 243 "What's new in UIKit"

Fetched. Relevant mechanics: traits are updated top-down during the layout pass, then
`updateProperties()` runs right after trait updates and before `layoutSubviews`;
`UIView.animate` option `.flushUpdates` applies pending invalidations just before the
animation begins and again when it ends. Frames appearance-change handling as
*invalidation within the update pass* — again, no recreation guidance.

### 2.5 WWDC23 10057 "Unleash the UIKit trait system" — why off-screen glass breaks

Fetched full transcript. Directly explains the rn-screens/expo "inactive tab" failures
and constrains any fix:

- *"Views only update their trait collection when they are in the hierarchy. And once
  in the hierarchy, each view only updates its trait collection immediately before it
  performs layout."* — a view that is off-screen/not in the hierarchy at flip time
  misses the trait update entirely.
- *"A view controller's view must be in the hierarchy for the view controller to
  receive updated traits."* Use `viewIsAppearing` (back-deploys to iOS 13), not
  `viewWillAppear`, for trait-dependent work.
- `traitCollectionDidChange` deprecated in iOS 17 → `registerForTraitChanges`;
  best practice: *"try to invalidate in response to trait changes without updating
  immediately"* (`setNeedsLayout`, not eager mutation).
- `systemTraitsAffectingColorAppearance` semantic set exists for exactly this
  invalidation use case.

### 2.6 Adopting Liquid Glass (tech overview doc)

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Fetched. Key lines: *"Reduce your use of custom backgrounds in controls and
  navigation elements. Any custom backgrounds and appearances you use in these elements
  might overlay or interfere with Liquid Glass."* *"Combine custom Liquid Glass
  effects… using a `GlassEffectContainer`."* Escape hatch documented at the bottom:
  `UIDesignRequiresCompatibility` Info-plist key keeps the pre-26 look. No appearance-
  change or recreation guidance.

### 2.7 Human Interface Guidelines

- Materials page fetched: https://developer.apple.com/design/human-interface-guidelines/materials
  — *"Don't use Liquid Glass in the content layer"*, *"use Liquid Glass effects
  sparingly"*, Regular vs Clear + dimming-layer rules. Nothing about appearance-change
  handling or animations on trait change.
- Segmented-controls page (https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
  returned only the JS nav shell on two fetch attempts (also via /cn/ mirror) —
  content unverifiable by me.

### 2.8 UIKit API docs (fetched via the DocC JSON endpoint; HTML pages are JS-only)

- `overrideUserInterfaceStyle` —
  https://developer.apple.com/documentation/uikit/uiview/overrideuserinterfacestyle
  (JSON: https://developer.apple.com/tutorials/data/documentation/uikit/uiview/overrideuserinterfacestyle.json)
  *"Use this property to force the view to always adopt a light or dark interface
  style… the new style applies to the view and all of the subviews owned by the same
  view controller… If the view is a `UIWindow` object, the new style applies to
  everything in the window."* No notes about animating the change or about glass.
- `traitCollectionDidChange(_:)` —
  https://developer.apple.com/documentation/uikit/uitraitenvironment/traitcollectiondidchange(_:)
  Deprecated iOS 17: *"Use the trait change registration APIs declared in the
  `UITraitChangeObservable` protocol."* Sample code checks that the specific trait
  actually changed before acting.
- `registerForTraitChanges(_:handler:)` —
  https://developer.apple.com/documentation/uikit/uitraitchangeobservable/registerfortraitchanges(_:handler:)
  (JSON fetched) — registers specific traits, closure form, returns an ignorable
  `UITraitChangeRegistration` token. No mention of animating trait-driven changes.
- Nowhere in any fetched Apple material: a note that glass elements must be in the
  hierarchy during appearance animation, or a recommendation to recreate views. The
  hierarchy requirement is only implied by WWDC23's trait-update rules (§2.5).

---

## 3. Empty or unverifiable leads

- **Telegram-iOS**: no recreation-on-appearance-change evidence. Telegram shipped its
  own custom glass (works pre-iOS 26), per
  https://9to5mac.com/2025/10/13/telegram-adopts-a-liquid-glass-like-design-no-ios-26-required/
  and https://livsycode.com/uikit/exploring-_uiportalview-live-view-replication-without-copying-or-snapshots/
  (private `_UIPortalView`/`_UILiquidLensView` references). A targeted
  Telegram-iOS + `overrideUserInterfaceStyle`/recreate search returned nothing relevant.
- **Apple Dev Forums recreate-thread URL**: post body seen in tag-listing excerpts
  (§1.8) but the thread permalink could not be resolved from fetched pages. Searches
  for its exact title only returned the tag listings.
- **HIG segmented-controls page**: JS-rendered shell via FetchURL (2 attempts, incl.
  /cn/ mirror). No HIG segmented-control guidance verified.
- **UIKit doc HTML pages** (overrideUserInterfaceStyle, UITraitChangeObservable):
  JS-only shells; `r.jina.ai` proxy returned 403; web.archive.org returned 429. Used
  the official DocC JSON endpoint instead (content verified, quoted above).
- **flutter/flutter + flutter/packages**: no issue found tying platform-view recreation
  to iOS 26 glass/appearance bugs. #170310 is only the Cupertino-redesign pause
  announcement. Searches for flutter platform view + iOS 26 glass artifacts surfaced
  only third-party packages and blog posts.
- **Blog posts (Medium/dev.to/kodeco/hackingwithswift)**: none found that prescribe
  control recreation specifically for iOS 26 glass state bugs; the genre is dominated
  by "disable via UIDesignRequiresCompatibility" (e.g. xorbix.com, dev.classmethod.jp)
  and styling workarounds. The concrete recreation prescriptions live on Stack Overflow
  and in package changelogs (§1.1, §1.5).
- **Flutter engine completeness**: `FlutterViewController.mm` fetch truncated before
  `traitCollectionDidChange:`; "no platform-view recreation on brightness change" is
  verified only for the fetched portion (init, lifecycle, settings-channel path).
- **callstack/liquid-glass #33**: fetched body contains no confirmed fix; listed as
  corroborating flakiness, not as a recreation citation.
