# Clip 08-13 defects A/B/C — code scan

Scan only, no code changed. Frames re-read from `/private/tmp/clip-0813/`
(`ev_search_slab.png`, `ev_toolbar_bare.png`, `c_tab_ghost.png` — still present).

## 0. Build provenance (settles what was actually running)

`kit/showcase_app/build/ios/Debug-iphoneos/Runner.app` mtime **2026-08-13
08:22:14**; recording starts 08:24. Every uncommitted working-tree source
predates it (`arxa_kit_animated_tab_stack.dart` 08-12 23:27,
`arxa_kit_native_toolbar.dart` 08-13 08:15).

**So the recorded binary already contained** the 0.5px `_HiddenTabClipper`
(`arxa_kit_animated_tab_stack.dart:340-364,416-424`), `platformViewSafe:
inScrollable` (`arxa_kit_glass_card.dart:69,92`), `preferFlutterTier:
inScrollable` on the toolbar (`arxa_kit_native_toolbar.dart:137,168`), and
vendor PATCH #5/#7. All three defects survive **every** fix landed on 08-12.
Do not re-land any of them as a fix for A/B.

## 1. The scroll-edge effect is NOT the mechanism (falsified, geometry)

Worth stating because it was the standing suspect (`liquid-glass-allowlist.md:89-94`).

`ArxaKitEdgeAwareListView` does wrap **every** child in
`ArxaKitScrollEdgeEffect` (`arxa_kit_edge_aware_list_view.dart:89-96,105-123`),
including the cards that host native sliders/switches — the banned
saveLayer-over-platform-views shape on paper. But:

- On iOS `supportsLiquidGlass` ⇒ `blurs == false` ⇒ `sigma == 0` always, so
  `ClipRect` stays `Clip.none` and the **only** live mutator is `Opacity`
  (`arxa_kit_scroll_edge_effect.dart:209-238`).
- At `t == 0` the chain is driven to identity — `Opacity(1.0)` pushes no layer
  (`:226-238`). `t` only leaves 0 inside the engage band, which for
  `occlusionPadding: kShowcaseTabBarBlockHeight = 64`
  (`showcase_tabs_consts.dart:12`) is roughly the bottom 64 logical px.
- **In both defect frames the broken widgets are mid-viewport.** `ev_search_slab.png`:
  RADIUS card at ~18-35% of viewport height, options section ~37-50%.
  `ev_toolbar_bare.png`: toolbar at ~59%. The band is >90%.

⇒ The effect was at identity and pushed no layer at either defect site.
A one-line `alpha = 1.0` probe will change nothing; skip it.

Separate, real, and *not* what the clip shows: every spacer and bare
`ShowcaseSectionLabelWidget` is its own effect child, so a ~16px-tall `Text`
hits `t == 1` (alpha 0.15) across a wide band while the tall card beside it is
at identity. That produces a *uniformly dimmed* label. The clip shows partial
glyphs, which is a different failure — keep the two apart.

## 2. DEFECT A — Search tab (`ev_search_slab.png`)

### Composited structure
`showcase_search_view.mobile.dart:42-67` → `ArxaKitEdgeAwareListView` children:
1. `ArxaKitNativeSearchBar` — **native** (CNSearchBar UiKitView)
2. `ShowcaseSearchFilterCardWidget` (`showcase_search_filter_card_widget.dart:27-59`)
   → `ArxaKitGlassCard` → in-scroll ⇒ `ArxaKitFrostedSurface(platformViewSafe: true)`
   ⇒ **plain `Container`, no BackdropFilter** (`arxa_kit_frosted_surface.dart:95-118`).
   Contents in paint order: `Text('RADIUS')` + chip (Flutter) → **CNSlider (native)**
   → `Text('PRICE RANGE')` + chip (Flutter) → **CNRangeSlider (native)**.
3. `ShowcaseSearchOptionsSectionWidget` → `ArxaKitListSection`
   (`arxa_kit_list_section.dart:84-91`) → `ArxaKitGlassCard` → same vibrant fill;
   rows are `ArxaKitListTile` (`Text` title, `arxa_kit_list_tile.dart:93`) with
   **CNSwitch (native)** trailing.

Section labels are plain `Text`, no wrapper of their own
(`showcase_section_label_widget.dart:29-39`).

### What the frame actually shows
- `RADIUS` + its `0.50` chip: **fine**. It is painted *before* any platform view.
- `PRICE RANGE` + its range chip: **gone**, one stray sub-glyph left. It is the
  content painted *between* CNSlider and CNRangeSlider.
- Options section: card fill **gone**, both tile labels **gone**; the two CNSwitch
  views composite correctly at the right x/y. A stale white rounded bar floats at
  ~(285-640, 935-1005 displayed) — wrong bounds for any card in that list.
- Measured at y=1500: from x=48 to x=888 the fill is RGB (243,236,229), against a
  page background of (232,225,218). So the card fill **is** being painted, but at
  the wrong intensity — `platformViewSafe` should give near-white (251,244,237).
  The boundary sits at x=48 = logical 16 = the list's left padding, i.e. the
  card's own left edge.
- At y=1240 a brighter (249,242,237) region spans x=364-816 — the stale white bar.
  Its bounds match no card in this list (all cards run x=48-1132).

### The "white slab" is identified
It is not a ghost from another tab. `ArxaKitFrostedSurface(platformViewSafe:
true)` paints `surfaceContainerLowest.withValues(alpha: 0.96)` — a near-opaque
white rounded rect with a white border and a shadow
(`arxa_kit_frosted_surface.dart:98-117`). That *is* the slab material. The
defect is that its rect is stale/mis-bounded, not that a foreign widget leaked.

### Hypotheses
**A1 (favoured) — inter-platform-view overlay slicing.** Flutter content that
must land in an intermediate overlay (above platform view N, below N+1) is
dropped or retains stale pixels; content in the base layer survives. Predicts
exactly the RADIUS-lives / PRICE-RANGE-dies split, the missing card fill behind
the switches, and the mis-bounded white bar.
*Killed by:* reorder the card so no Flutter text sits between two platform views
(move `PRICE RANGE`'s row above `ArxaKitNativeSlider`,
`showcase_search_filter_card_widget.dart:38-51`). If the label then survives at
the same scroll offsets, A1 holds; if it still dies, A1 is wrong.

**A2 — frame platform-view count / hidden-tab views.** The clip bounds a hidden
tab's *pixels* but deliberately keeps its UiKitViews in the native hierarchy
(`arxa_kit_animated_tab_stack.dart:316-339`). Visiting Home/Profile/Notes
therefore adds their platform views to every Search frame (Profile alone adds 5
native buttons — `arxa_kit_native_button.dart:99-104` keeps buttons native
in-scroll, only style-mapping glass→tinted).
*Killed by, zero code:* fresh launch → straight to Search → scroll (only Home+Search
in `_initialized`). Then visit Profile and Notes, return to Search, scroll again.
Defect absent on the first pass and present on the second ⇒ A2 holds.
**Run A2 before A1** — it costs nothing and, per
`liquid-glass-allowlist.md:101-107`, the keep-alive must not be touched without
exactly this evidence.

**A3 — `platformViewSafe` is an incomplete guard.** It removes the BackdropFilter
but keeps a `boxShadow` (`arxa_kit_frosted_surface.dart:107-113`), which still
forces a compositing pass. *Killed by:* drop that shadow and re-record. Weakest
of the three; run last.

## 3. DEFECT B — Profile toolbar (`ev_toolbar_bare.png`)

### Composited structure
`showcase_profile_view.mobile.dart:63-113` list → `const ShowcaseProfileToolbarDemoWidget()`
→ `ArxaKitNativeToolbar` (`showcase_profile_toolbar_demo_widget.dart:27-46`)
→ `_glass()` with `preferFlutterTier: Scrollable.maybeOf(context) != null`
(`arxa_kit_native_toolbar.dart:137,168`) ⇒ `CNGlassButtonGroup` takes
`_buildFlutterFallback` (`glass_button_group.dart:252-254,558-582`, a `Wrap`),
children inherit the tier via PATCH #7 (`:594-601`) and get PATCH #5's
`foregroundColor` (`button.dart:1310-1327`).

**`preferFlutterTier` cannot vary with scroll offset** — `Scrollable.maybeOf` is
an InheritedWidget lookup, constant for this element. So B is *not* a tier flip,
and the "three states" are not three tiers.

### What the frame actually shows
- Share: lavender wash pill + glyph, **no label**.
- Edit / Delete: bare dark glyphs, **no pill fill, no label**; Delete is not red
  despite `isDestructive: true` ⇒ `tint: scheme.error`
  (`arxa_kit_native_toolbar.dart:155`).
**RETRACTED — an earlier draft of this section claimed the same frame drew the
TOAST & SHEET card inset to x≈78-845 with "Show sheet" clipped at that edge.
Pixel measurement disproves both.** The card's right edge is at x=1132 (logical
377.3), exactly the list's right padding; the "Show toast" pill spans x=100-1079
symmetrically; and "Show sheet"'s purple span shrinking from 1079 (y=2060) to
965 (y=2090) is the FAB circle occluding it, which is normal. Those readings came
from eyeballing a 0.78×-downscaled image. Do not reuse them.

### What measurement does support
One real anomaly survives: a band at x=48-99 (logical 16-33) down the toolbar
frame's left edge renders RGB (243,236,229) where the card fill is (251,244,237)
— the card's leading 17 logical px are drawn at the wrong intensity, and only on
the left. The *same* (243,236,229) value fills the dead region in
`ev_search_slab.png` at y=1500, x=48-888, where a near-white card fill belongs.
So the two frames share a wrong-fill colour and a boundary at x=48 (the list
padding line); the toolbar frame has a second boundary at x=99 that the search
frame does not. **Partial agreement — suggestive, not conclusive.**

### Hypotheses
**B1 — same mechanism as A1/A2**, i.e. B and A are one defect. Support: native
content survives while Flutter content degrades in both frames; the shared
(243,236,229) wrong-fill value; and the fallback is a `Wrap`
(`glass_button_group.dart:564-569`), which cannot produce the "overlapping pill
backgrounds" the sweep doc records, so that state is not layout overflow.
*Confidence is low and the reason is the evidence base, not the reasoning:*
**B rests on one frame.** `c_toolbar_bare.png` is a 1180×500 crop of the same
frame, not a second moment, and the t≈14.5s and t≈15.9s states the sweep doc
describes survive only as 2fps contact-sheet thumbnails. Before B1 is treated as
established, re-extract full-res frames at those two timestamps from the MP4.
*Killed by:* the A2 fresh-launch probe. If Search comes back clean on a fresh
launch, re-run the same probe on Profile. A shared cause predicts both clean.

**B2 — element lifecycle / async re-resolution.** The toolbar is child ~4 of 12;
past `ListView`'s default 250px `cacheExtent` the group's State disposes, and
scrolling back restarts `syncResolution()` — `_buildNativeGroup` renders an
estimated-width placeholder while `resolvedValue == null`
(`glass_button_group.dart:305-320`). Would explain offset-dependence and
partial per-button rendering.
*Killed by:* pass a large `cacheExtent` to the `ListView` in
`arxa_kit_edge_aware_list_view.dart:85-96` and re-record. Note this predicts
nothing about the mis-bounded TOAST & SHEET card, so it cannot be the whole story.

**B3 — PATCH #5 foreground still lands tone-on-tone.** `_effectiveTint` for a
null-tint glass button may resolve to a colour matching the wash.
*Killed by:* a widget test pumping the fallback and reading the resolved
`DefaultTextStyle` colour vs the button fill. Cheap, but it cannot explain the
missing *pill fills* on Edit/Delete or the clipped neighbouring cards — treat as
a secondary cleanup, not the cause.

## 4. DEFECT C — tab-bar lens (`c_tab_ghost.png`)

### Composited structure
`showcase_application_tab_host_widget.dart:123-140` → `ArxaKitNativeTabBar`
→ iOS 26 branch `CNTabBar` (`arxa_kit_tab_bar.dart:85-158`) with
`CNTabBarItem(label:, icon: CNSymbol(sfSymbol))` (`:138`), `iconSize: 0`
sentinel so UIKit does its own HIG symbol sizing (`:140-143`), and
`shrinkCentered: false` for fixed geometry (`:144-153`).

Native side builds real `UITabBarItem(title:image:selectedImage:)`
(`CupertinoTabBarPlatformView.swift:186`, and again at `:551`, `:667`) on a real
`UITabBar` (`:203-204,339`).

### Correction to the sweep doc
**There is no Flutter icon or label content in this frame.** Titles and images
are UIKit's, rendered inside the platform view; the lens is `UITabBar`'s own
iOS 26 selection indicator. "The lens duplicates Flutter content" is a
misdescription — nothing Flutter-drawn is available for it to duplicate.

What the frame shows is consistent with UIKit's own behaviour: the smeared
purple blob at the lens's leading edge is refraction of the Home glyph, and the
half-purple / half-black magnifier plus "S"-purple / "rch"-black split is the
selected-tint boundary tracking the lens edge mid-slide.

### Hypotheses
**C1 (favoured) — by design.** iOS 26 matched-geometry lift + refraction.
*Killed by:* the stock-UITabBar reference comparison the sweep doc already asked
for. This is the only discriminator; no Flutter-side probe can settle it.

**C2 — forced geometry exaggerates it.** `shrinkCentered: false` (`:153`) pins
full-width fixed item positions, which stock iOS 26 does not do — the indicator
may be sized for a layout UIKit did not choose.
*Killed by:* flip `shrinkCentered` to its default in a scratch build and compare
the slide. Note `:144-152` records why it was pinned (items sliding 15-20pt,
taps landing on neighbours) — this is a diagnostic probe, not a proposed fix.

## 5. Recommended order

This scan changed no code, as briefed. **A2 and C1 are the only probes runnable
without touching code**; A1, A3, B2 and C2 all require a source edit and are
proposed here for the lead to schedule, not steps taken.

1. **A2 fresh-launch probe** (zero code, settles A and B together).
2. **Re-extract full-res frames at t≈14.5s and t≈15.9s** from the MP4 — B
   currently rests on a single frame and two of its three recorded states have
   never been inspected above thumbnail scale.
3. If A2 is clean on first pass: instrument the frame's platform-view count
   before deciding anything about the keep-alive.
4. **C1 stock-UITabBar comparison** — independent of 1-3, can run in parallel.
5. A1 reorder and B2 `cacheExtent` (both code edits) only if A2 comes back
   negative.

## 6. Confidence

- **§0 build provenance** — verified from filesystem mtimes.
- **§1 edge effect falsified** — verified: geometry plus the iOS `sigma == 0`
  branch. High confidence.
- **§2 defect A** — the composition path and the slab's material identity are
  read directly from source; the wrong-fill and stale-bar rects are measured.
  A1 vs A2 is unresolved and A2 is untested.
- **§3 defect B** — one frame, one retracted claim. Low confidence; treat B1 as
  a lead, not a finding.
- **§4 defect C** — the native-content correction is verified from the Swift
  (`UITabBarItem(title:image:selectedImage:)`). Whether the look is a defect at
  all is unresolved and needs the reference comparison.
