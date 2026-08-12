# iOS 26 UISegmentedControl "lens" — lighter re-render levers & animation interruption

Research date: 2026-08-12. Method: web search + full-page fetches only (Stack Overflow
direct-fetch is 403-blocked for bots; SO pages were read through the r.jina.ai mirror —
content verified verbatim, original URLs cited). Apple Developer Forums threads are behind
a "Security Verification" wall; where a forums thread could not be fetched, it is marked
**snippet-only** (title/excerpt seen in search results, body unverified).

Context recap: Flutter hybrid platform view hosting a native `UISegmentedControl` on
iOS 26; an app-driven `overrideUserInterfaceStyle` flip lands while the Liquid Glass
selection "lens" slide is in flight; `removeAllSegments()` + re-insert inside a
no-animation `CATransaction`+flush leaves a frozen semi-transparent lens smear for ~1–2 s.
Full view recreation cures it. Question: is there a lighter documented lever?

**Bottom line:** No one has published a confirmed "nudge the lens to re-composite" trick.
Everything confirmed-working is one of: (a) wrap programmatic selection changes in
`UIView.setAnimationsEnabled(false)`, (b) re-set `selectedSegmentIndex` to snap the lens
to a valid position, (c) don't restructure the control mid-gesture/mid-animation (defer to
touch-up), or (d) destroy/recreate — which the ecosystem has converged on exactly like we
did. Direct evidence that `setNeedsDisplay`/`layoutIfNeeded`-class nudges fix iOS 26
glass-compositing staleness does not exist; adjacent evidence says they don't reach the
render-server-side lens.

---

## Levers — evidenced-worked

### 1. `UIView.setAnimationsEnabled(false) … true` around programmatic selection changes — iOS 26, CONFIRMED
`cupertino_native_better` (Flutter package hosting native UITabBar/UISegmentedControl via
platform views — same architecture as ours). Their Swift `refresh` cycled
`bar.selectedItem` through every tab to force label layout (workaround for an older
missing-labels bug). On iOS 26 that cycling became visible as **the Liquid Glass selection
pill morphing through every tab**. Fix shipped in v1.4.5: wrap the cycle in
`UIView.setAnimationsEnabled(false) … true` — "labels still render correctly, but the pill
no longer animates between items."
- Who/where: gunumdogdu/cupertino_native_better CHANGELOG (v1.4.5, issues #35/#41), fetched in full.
- URL: https://github.com/gunumdogdu/cupertino_native_better/blob/main/CHANGELOG.md
- Relevance: proves (a) the lens/pill animates on *programmatic* selection changes, and
  (b) `setAnimationsEnabled(false)` suppresses that animation. This is stronger than
  `CATransaction.setActions`/`performWithoutAnimation` for system controls because it
  gates UIKit's own animation paths, not just CA actions.

### 2. Re-setting `selectedSegmentIndex` restores/snaps a wedged lens — iOS 26, CONFIRMED
SO 79877797: lens ("liquid glass handle") **freezes mid-air** when dragged onto a segment
disabled via `setEnabled(false, forSegmentAt:)`. OP's own manual recovery: "tap on any
other segment to restore its position" — i.e., a selection change un-wedges the lens.
Accepted answer (OP confirmed "This works!"): keep the segment technically enabled, render
its title as a dimmed image, and in `.valueChanged` snap back with
`segmentView.selectedSegmentIndex = 1` when the disabled index is hit. Filed with Apple as
FB21783594 / FB21783580.
- URL: https://stackoverflow.com/questions/79877797/liquid-glass-segmented-control-freezes-when-dragging-handle-to-a-disabled-segmen (read via mirror; Apple forums cross-ref: https://developer.apple.com/forums/thread/813673 — bot-walled, unverified)
- Relevance: programmatically re-assigning `selectedSegmentIndex` *does* drive the lens to
  a new position even when it's visually stuck. A "re-set to current value" nudge is
  untested anywhere (all reports re-set to a *different* value), but the mechanism reaches
  the lens.

### 3. Destroy/recreate the platform view (or keep it mounted) — iOS 26, CONFIRMED (validates our cure)
Same package, two data points:
- ModalHideMixin (v1.5.1, issue #53): all 9 native-glass widgets **destroy their
  PlatformView and recreate it** when a sheet covers them — recreation as the sanctioned
  reset for hybrid-composition artifacts.
- Recreate-on-return bug (v1.4.5, issue #41): when the platform view *was* destroyed and
  re-created, the fresh control visibly animated the lens to the restored index
  ("visible animate-to-index"). Fix: keep the same `UiKitView` mounted (IndexedStack
  toggle) so the native control survives — i.e., they moved *away* from recreation to avoid
  lens animation, the mirror image of our situation.
- URL: https://github.com/gunumdogdu/cupertino_native_better/blob/main/CHANGELOG.md
- .NET MAUI side agrees: iOS 26 tab-bar "ghosting" (selected item empty, ghosting
  artifacts) — only workarounds are `UIDesignRequiresCompatibility=YES` or changing
  navigation structure; no in-place fix. Fetched in full:
  https://github.com/dotnet/maui/issues/34143

### 4. SwiftUI `.id(x)` forced-recreation trick — ecosystem-standard, CONFIRMED as practice
Documented as the "last resort" force-refresh: livsycode ("Using .id(_:) tied to a
changing value such as a UUID is a straightforward way to force a SwiftUI view to reload")
and Big Mountain Studio ("Method 4: Using the id Modifier … Last resort").
- URLs (search-verified, pages not fetched): https://livsycode.com/swiftui/forcing-a-view-reload-in-swiftui/ , https://www.bigmountainstudio.com/blog/swiftui-refresh-methods-explained
- Relevance: even inside Apple's own declarative stack, the accepted way to clear stale
  visual state is *identity change = recreation*, not invalidation. Supports recreation as
  the idiomatic cure.

### 5. Adjacent: stale dynamic colors are only cured by a redraw/recreation cycle — iOS 13/14, CONFIRMED
Jesse Squires, "Fixing a hard-to-find bug in Dark Mode": buttons whose colors were derived
through a non-dynamic `UIColor` extension got "stuck" showing the previous appearance after
a Control-Center dark-mode flip; "if you performed an action to trigger a redraw or refresh
of the UI" (dismiss the view and return — i.e., recreate) "the button colors … would get
back in sync". No lighter nudge is reported.
- URL (fetched): https://www.jessesquires.com/blog/2021/07/15/fixing-a-hard-to-find-bug-in-dark-mode/
- Relevance: same failure shape as ours (appearance flip → stale composited/painted state)
  on pre-Liquid-Glass iOS; the fix was removing the root cause, and recreation was the only
  *post-hoc* clearer.

---

## Levers — evidenced-failed

### 1. `layoutIfNeeded()` after dynamic segment rebuild — iOS 26, FAILED (adjacent symptom)
DevelopersIO (fetched in full): iOS 26 + `UIDesignRequiresCompatibility=YES` +
`removeAllSegments()`/`insertSegment(animated:false)` → hit-testing misaligned (tap right
segment, left selects). "**Calling layoutIfNeeded()** … unfortunately, this approach didn't
work." Only workarounds: static segments or `UIDesignRequiresCompatibility=NO`.
(FB21712773, forums thread 813511.)
- URL: https://dev.classmethod.jp/en/articles/xcode26-uisegmentedcontrol-tap-position-bug/
- Relevance: different symptom (hit-test vs compositing) but the same operation as ours
  (removeAll+re-insert on iOS 26) and proof that layout nudges do not reset iOS 26
  segmented-control internal state.

### 2. Simulator-only workarounds that fail on physical hardware — iOS 26, FAILED on device
Plugin.SegmentedControl.Maui issue #38 (fetched in full): SegmentedControl invisible inside
`Shell.TitleView` on iOS 26; layout workarounds (explicit height container, eager children)
make it appear **on the simulator only** — "these workarounds fail on a physical device …
a deep issue with the native hardware rendering pipeline on iOS 26."
- URL: https://github.com/thomasgalliker/Plugin.SegmentedControl.Maui/issues/38
- Relevance: warns that any lens-smear fix validated only on the simulator (software
  rasterization) may not hold on Metal hardware. cupertino_native_better's changelog says
  the same: "iOS 26 Liquid Glass rendering on the simulator is software-rasterized … Always
  verify … on a real iPhone/iPad."

### 3. `setNeedsLayout`/`setNeedsDisplay` forced redraws — weak adjacent failure evidence
Apple forums TVUIKit/focus thread (**snippet-only**): "We tested 10 different approaches,
none worked: … Forcing UIKit redraws (setNeedsLayout, setNeedsDisplay) …". Different domain
(focus engine, tvOS) — included only because it's the sole located report of someone
explicitly trying the invalidation pair against a stale UIKit rendering state and failing.
- URL (unverified body): https://developer.apple.com/forums/tags/tvuikit

---

## Levers — speculation (no confirming evidence found either way)

| Lever | Verdict | Notes |
|---|---|---|
| `setNeedsDisplay` / `setNeedsLayout` on control or subviews vs the lens | SPECULATION (weak negative) | No iOS 26 report of these clearing a glass/lens artifact. The lens renders via the render server (see `_UILiquidLensView` below), so view-level invalidation plausibly never reaches it; only the tvOS-focus snippet above is a direct try-and-fail. |
| Re-set `selectedSegmentIndex` to the **same** value | SPECULATION | Re-set to a *different* value is confirmed to move a wedged lens (Levers-worked #2). Same-value no-op behavior undocumented — cheap to test on device. |
| Toggle `isMomentary` / `isEnabled` / `isUserInteractionEnabled` | SPECULATION | Zero reports found, any iOS version, as a redraw lever. (`setEnabled(false, forSegmentAt:)` on iOS 26 is actively harmful — freezes the lens, SO 79877797.) |
| Re-set `selectedSegmentTintColor` / `tintColor` | SPECULATION | Found only unrelated iOS 26 tint bugs: selectedSegmentTintColor ignored on segmented-in-bar-button-item (Apple forums Beta tag, snippet-only), tint re-apply needed after nav-bar layout (https://www.volcengine.com/article/31325, snippet-only). Nobody uses tint re-set as an invalidation lever. |
| `layer.setNeedsDisplay`, `layer.setNeedsLayout`, `setNeedsDisplayOnBoundsChange` | SPECULATION | No reports. CALayer-level invalidation only re-runs `display`/layout — it does not discard composited render-server content, which is where the smear lives. |
| `CATransaction.flush()` | SPECULATION (semantics documented, effect unproven) | Flush "pushes UI changes to the render server" (https://danielkbx.com/post/108060601989/catransaction-flush; SO 42420178 answer snippet). Nobody reports flush clearing a stale lens — it commits *pending* changes; it does not force re-composite of already-committed frames. Apple doc page exists but is JS-walled (content unverified): https://developer.apple.com/documentation/quartzcore/catransaction/flush() |
| `isHidden` / alpha toggle, `removeFromSuperview` + re-add **same** instance | SPECULATION | No iOS 26 glass reports. Historical dark-mode/`CGColor` staleness was only cured by real recreation (Levers-worked #5). |
| Snapshot-and-swap (`snapshotView(afterScreenUpdates:)`) | SPECULATION + hazard note | `afterScreenUpdates:false` captures "the current GPU framebuffer immediately without waiting for pending render passes" (PostHog issue, fetched-snippet level: https://github.com/PostHog/posthog-ios/issues/524) — i.e., a snapshot taken mid-smear can bake the stale frame in. |
| Private APIs: `_setSelectionIndicator…`, `_setSelectedSegment…`, KVC on internal views | SPECULATION, App-Store-risky | The lens class exists and is named: `_UILiquidLensView` appears around Liquid Glass UI in runtime inspection, part of the same compositor-side family as `_UIPortalView`/`CAPortalLayer` (fetched: https://livsycode.com/uikit/exploring-_uiportalview-live-view-replication-without-copying-or-snapshots/). Crucially, that article documents the portal/lens path going **stale by design** when content updates via surface swaps rather than layer-tree mutations — matching our smear mechanics. No selector to force lens invalidation is documented anywhere. KVO/KVC on private `UISegment` subviews is an old documented hack (pre-iOS 13: https://happts.github.io/2019/08/23/customsizeUISegmentedControl/, SO 2270526) but targets colors, not the iOS 26 lens. |
| Trait nudge: re-assign `overrideUserInterfaceStyle`; call `traitCollectionDidChange` manually; window/VC-level override | SPECULATION (manual call: don't) | No reports of re-assigning the same override value as a refresh nudge. `traitCollectionDidChange:` is deprecated since iOS 17 in favor of `registerForTraitChanges:` and documented as system-invoked (flutter/flutter#128735: https://github.com/flutter/flutter/issues/128735; Apple doc discussion text seen in search). Calling it manually would not re-run UIKit's internal trait handlers anyway. |
| `.id(x)`-style identity bump for UIKit | N/A — SwiftUI-only mechanism | Listed under worked #4 as ecosystem direction-of-travel evidence. |

---

## Animation interruption findings

**Does the lens animate as CAAnimation on a private subview, and can it be cancelled?**
- The selection indicator is compositor-side on iOS 26: `_UILiquidLensView`, in the same
  private rendering family as `_UIPortalView`/`CAPortalLayer` (livsycode, fetched — URL
  above). No one has published a `layer.removeAllAnimations()`-style cancellation against
  it. Generic "cancel a UIView animation" answers (SO 554997) predate Liquid Glass and
  target app-owned layers. → interruption via layer surgery: **no evidence, risky**.
- Confirmed alternative to cancellation: **prevent the animation from starting** —
  `UIView.setAnimationsEnabled(false)` suppresses the lens morph on programmatic selection
  changes (Levers-worked #1). This is the strongest actionable lever found.

**removeAllSegments()/insertSegment mid-slide — known glitches?**
- No report ties removeAll+re-insert *during the lens slide* to smears (our exact scenario
  appears undocumented publicly). Closest iOS 26 reports around dynamic segment mutation:
  the hit-test misalignment bug (DevelopersIO, fetched) and the disabled-segment lens
  freeze (SO 79877797, fetched) — both involve `removeAllSegments()` setups but attribute
  the bug to iOS 26 state handling, not to mid-animation timing.

**Don't restructure mid-gesture: the deferral pattern — well documented**
- `liquid_glass_widgets` (Flutter glass package) changelog, fetched in full
  (https://pub.dev/packages/liquid_glass_widgets/versions/0.21.5/changelog):
  - "Tab bar freeze fixed … The iOS gesture arena can silently drop terminal callbacks,
    leaving the recognizer wedged" when clip layers are added/removed mid-gesture;
    "iOS reconstructs the platform-view clip chain whenever a clip layer is added or
    removed mid-gesture. The engine responds by cancelling the active touch."
  - "Hybrid gesture mode … the visual indicator now animates to its new position instantly
    on touch-down … while the actual tab content swap is **deferred safely to touch-up**.
    This prevents the iOS UIKit view system from dropping the touch stream mid-gesture due
    to a mid-frame unmount."
  - Same package: a stuck-state recovery that bumps a `ValueKey` to tear down/recreate the
    detector — again recreation as the reset.
- Cross-ecosystem analog: React Native's `InteractionManager.runAfterInteractions` defers
  work until transition animations finish (example write-up, snippet-only:
  https://rorklab.net/en/articles/rork-dev/rork-animation-jank-frame-drop-debug-fix).
- For our case this maps to: apply the `overrideUserInterfaceStyle` flip and/or the
  segment rebuild on `.touchUpInside` (or after a short settle delay) instead of
  `.valueChanged` (which fires on touch-down, while the lens slide is starting). No
  published source tests this exact mapping — it is an inference from the sources above.

**UIKit docs on indicator animation timing/threading**
- Nothing found. Apple's UISegmentedControl documentation has no discussion of selection
  animation timing or compositing; `CATransaction.flush()` docs are JS-walled
  (unverified). General render-server/transaction architecture write-up (snippet-only):
  https://vbat.dev/behind-the-scenes-of-ui-part-1-uikit

**Simulator vs device caveat (repeated independently)**: Liquid Glass is
software-rasterized on the simulator; multiple packages report artifacts that differ or
vanish on hardware (cupertino_native_better changelog; Plugin.SegmentedControl.Maui #38).
Any lever test must run on a physical device.

---

## Empty searches (negative results — looked, nothing found)

- `_setSelectionIndicator` / `_setSelectedSegment` / underscored UISegmentedControl selectors: **no hits**.
- `layer.removeAllAnimations()` on UISegmentedControl subviews / lens cancellation: **no hits** (only generic pre-2026 UIView-animation cancellation).
- `isHidden` / alpha toggle / removeFromSuperview+re-add-same-instance as an iOS 26 glass invalidation trick: **no hits**.
- Re-assigning `overrideUserInterfaceStyle` (same value) as a refresh nudge; UIViewController/UIWindow-level override vs per-view for glitch avoidance: **no hits**.
- Telegram-iOS liquid-glass rendering glitches: **no hits** (Telegram appears only as a reference *user* of `_UIPortalView`-style techniques in the livsycode article).
- callstack `@callstack/liquid-glass` / expo glass segmented-control lens smear reports: **no hits** (packages exist; no glitch reports on segmented lens smears).
- Apple documentation on UISegmentedControl selection-animation timing or indicator compositing: **does not exist**.
- Apple Developer Forums threads 789898 ("UISegmentedControl Not Switching Segments on iOS Beta 26"), 813673, 813511, 806665 ("iPadOS 26.1 traitCollection dark-mode bug"): **bot-walled, bodies unverified** — titles/snippets only. (789898: native UISegmentedControl not switching on iOS 26 beta; 806665: "The appearance of the UI changes, but no longer for view controllers" — likely relevant if fetchable.)
- SO 79826825 "Segmented control has design bugs in Navigation Bar with Liquid Glass": exists (seen in SO related-questions list) but mirror fetch was rate-limited — **unverified**.
- flutter/flutter #170310 (Liquid Glass support request — Flutter team not shipping it) and flutter/flutter #34330 (platform-view + slivers rendering glitches, 2019): **search-snippet only**, general platform-view rendering fragility, not lens-specific.

## Practical takeaway for our bug

1. Cheapest untested-but-plausible lever: **defer the style flip + segment rebuild to
   `.touchUpInside`/post-gesture** instead of `.valueChanged` (deferral is the one pattern
   with cross-package confirmation).
2. Next cheapest: **`UIView.setAnimationsEnabled(false)`** around the rebuild instead of
   (or under) the no-animation CATransaction — confirmed to gate the iOS 26 lens animation
   path where CATransaction tricks may not.
3. A `selectedSegmentIndex` re-set to a *different-then-back* value is confirmed to
   re-drive the lens and could clear a wedge; same-value re-set is untested.
4. If smears persist on device: recreation remains the only universally-confirmed cure —
   and is exactly what the ecosystem (MAUI, cupertino_native_better, liquid_glass_widgets)
   ships. Validate every candidate on **physical hardware**, not the simulator.
