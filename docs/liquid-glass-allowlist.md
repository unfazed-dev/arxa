# Liquid Glass allowlist — what renders native, where

Single source of truth for which kit widgets are native platform views, which
carry Liquid Glass, and what happens inside scrollables. Governing principle
(decided 2026-08-12, grilled): **Apple-fidelity — the kit does exactly what
iOS 26 does, nothing more, nothing less.** When a dispute arises, the answer
is "what does Apple's own app do here?", verified against the sources at the
bottom, not taste.

## The three classes

### 1. Chrome — native glass, always
Fixed elements floating above content. Glass is *reserved* for this layer
(WWDC25 219: "Liquid Glass is best reserved for the navigation layer").

| Kit widget | Notes |
|---|---|
| AppBoxKitTabBar / CNTabBar | |
| AppBoxKitNativeToolbar (as chrome) | Scaffold-anchored bars only — see §3 for in-content demos |
| AppBoxKitNativeFab / FabMenu | Scaffold FAB slot |
| AppBoxKitNativeSheet / NativeDialog / NativePopupMenu | Transient overlays |
| AppBoxKitNativeSearchBar (docked/pinned) | Pinned sliver headers count as chrome |
| AppBoxKitNativeAppBar / SliverAppBar | Already Flutter-drawn; native glass optional future |

### 2. Controls — INFORMED ALLOWLIST (ratified 2026-08-13, supersedes both prior rulings)
Button-class controls stay **native Liquid Glass everywhere, including
scrollables**; continuous/text controls take the **Flutter tier inside
scrollables**. Native everywhere outside scrollables and in all chrome, for
every control.

Evidence trail (all three states device-observed, 2026-08-13):
1. Native-everywhere: artifacts on Search/Profile scroll (clips 08-24, 11-34).
2. Full demotion (`4af16e3f`): artifacts GONE — slicing mechanism confirmed
   (engine #150646, open through Flutter 3.47.0; overlay rects ignore clip
   bounds).
3. Home's 7 `AppBoxKitNativeIconButton`s — real UiKitViews inside a ListView,
   never gated — rendered clean the whole time: CNButton-backed views are
   exposure-safe in practice. Exposure is compositional, not categorical.

| Kit widget | In-scroll behavior |
|---|---|
| AppBoxKitNativeButton / IconButton | **native glass**, styles pass through 1:1 |
| AppBoxKitNativeSplitButton | **native glass** (CNGlassButtonGroup) |
| AppBoxKitNativePopupMenu (in-content trigger) | **native glass** |
| AppBoxKitNativeSegmentedControl | **native glass** — first to re-demote if artifacts return |
| AppBoxKitNativeSlider / RangeSlider | Flutter tier (clip-proven offender) |
| AppBoxKitNativeSwitch | Flutter tier (clip-proven offender) |
| AppBoxKitNativeSearchBar (in-form) | Flutter tier (slab-central in clips) |
| AppBoxKitNativeTextField | Flutter tier |

Mechanism for the demoted set:
`preferFlutterTier: Scrollable.maybeOf(context) != null` (with PATCH
#5/#7/#8/#9 fallback fixes). The re-promoted set passes no tier flag.

**Known deviation from HIG, accepted knowingly:** Apple's Materials page says
"Don't use Liquid Glass in the content layer" and gives in-list
sliders/toggles glass only *during activation*. The demoted set matches that.
The button-class re-promotion deviates (resting glass buttons in scroll) —
user-ratified 2026-08-13 as a deliberate product choice, backed by home's
clean rendering.

**Deselect protocol (if artifacts reappear in a scrollable):** re-demote ONE
control type per device run, starting with segmented, then popup menu, then
split button, then button. Never blanket-demote again — attribution first.

### 3. Glass surfaces — demoted inside scrollables, native when static
Applied glass (platters, cards, containers) scrolling with content is Apple's
named anti-pattern ("don't break the glass… keep glass out of the scrolling
content layer" — WWDC25 design lab) and the vendor's own README forbids
LiquidGlassContainer in scrolling lists.

| Kit widget | In-scroll behavior |
|---|---|
| AppBoxKitGlassCard | AppBoxKitFrostedSurface(platformViewSafe: true) — vibrant fill, NO BackdropFilter |
| AppBoxKitNativeToolbar (in-content demo) | demoted via preferFlutterTier (propagates to children) |

**Composition rules (learned on device, 2026-08-12 evening):**
1. **No saveLayer effect may wrap a subtree that may host platform views** —
   BackdropFilter, partial-alpha Opacity, ShaderMask, ImageFiltered alike.
   The saveLayer cannot span the frame slices UiKitViews create; Flutter
   content inside it drops or ghosts per frame (flutter#175048;
   kit/core/NATIVE_COMPONENTS.md). In-scroll surfaces use the vibrant-fill
   variant — which is also Apple's own degrade for nested glass.
2. **Demoting a composite widget must propagate the tier to its children.**
   CNGlassButtonGroup's fallback rebuilt child configs without
   `preferFlutterTier`, silently re-promoting them to native UiKitViews
   inside the scrollable (vendor LOCAL PATCH #7 fixes this). Any future
   composite fallback must inherit the parent's tier.
3. **Alpha-hiding a platform-view-rich subtree is not containment — clip it
   too.** A tab kept alive at 0.004 alpha still paints every frame; its
   platform views slice the ACTIVE tab's frame into overlay textures, and
   pieces of the hidden subtree composited over the active tab at visible
   alpha (stale rail-pane rectangle over Profile, "Maps showcase" ghost over
   Search — device recording 2026-08-12 22:46). AppBoxKitAnimatedTabStack now
   pairs the alpha-hide with a sub-pixel ClipRect: paint still happens (the
   views never detach — 00bc2f0c's guarantee holds), but a hidden tab can
   contribute at most half a pixel to the frame.
4. **Native views must not cull at a mid-screen viewport edge (clips 12-48,
   13-17).** The engine drops a platform view the moment it stops being
   painted and re-materializes it on re-entry with a visible glass shimmer.
   Sliver child culling is **layout-based**, not clip-based:
   `RenderSliverMultiBoxAdaptor.paint` skips a child once
   `mainAxisDelta + paintExtent <= 0` at the viewport's leading edge —
   `clipBehavior` never participates, so the first fix (`Clip.none`,
   35ed8ec0) was inert and clip 13-17 showed the seam shimmer unchanged.
   Working fix: `AppBoxKitEdgeAwareListView(extendBehindTopBar: true)`
   oversizes the viewport upward (OverflowBox, bottom-aligned; overdraw
   returned as top padding) so the leading edge sits at/above the physical
   screen top and culling happens off-screen — the same lifecycle
   `extendBody: true` gives the bottom edge. ONLY under opaque chrome (the
   bar paints after the body and covers the overdraw; the overflow is
   paint-only, taps above the body still hit the bar).
   `Scaffold.extendBodyBehindAppBar` was rejected twice: the gallery body
   hosts nested-route Scaffolds whose own bars would inherit the inset
   shift.
5. **Fill color and foreground travel together in fallbacks.** Any fallback
   that sets a CupertinoButton `color` must set the foreground too: solid
   fill → contrasting color, translucent tint wash (glass) → the tint itself
   (vendor PATCH #5). The default foreground flips with `color` and lands
   tone-on-tone both ways (auth's blank Sign In; the profile toolbar's blank
   Share/Edit/Delete).

**Resolved residual (2026-08-13, clip 12-48):** `AppBoxKitScrollEdgeEffect`'s
partial-alpha fade over edge-band children hosting native controls produced
exactly the predicted artifact (home's smoke row + Glass CTA: glyphs washed
out ahead of the shell, pale ghosts, pop-in on re-entry). Fix landed: the
effect is now **fully inert on the Liquid Glass tier** (alpha gated alongside
the blur) — children exit by plain viewport clipping, which is what iOS does
under opaque chrome anyway and costs zero layers. The frosted tiers keep the
blur + fade (pure Flutter under the saveLayer). Pinned by
`appbox_kit_scroll_edge_effect_tier_test.dart`.

**Deviation note — split button:** obsolete — under the informed allowlist
(§2) CNSplitButton is native in content by rule, not by deviation.

## Performance policy (decided with the allowlist)
Platform-view cost scales per live view per frame (no cliff; ~45 MB and a
render-target switch per view — flutter#46666, #40108). The tab stack's
alpha-keep-alive means visited shells keep compositing. Policy: **land, then
measure on device**. The keep-alive (anti-flicker, commit 00bc2f0c) is not to
be touched without device evidence that it is the bottleneck — this codebase
has twice killed a correct mechanism to protect a defective one.

## History
- Round 1–2 (2026-08-12): blanket in-scroll demotion of all natives shipped
  and was reverted for controls the same day — it enforced a rule Apple only
  holds for glass *surfaces*. See docs/plans/scrollable-glass-demotion.md.
- Round 3 (2026-08-13): full control demotion (`4af16e3f`) on the clip-0813
  probe trail; device run confirmed artifacts gone (mechanism proven), then
  superseded same day by the informed allowlist (§2) once home's ungated
  in-scroll icon buttons proved button-class views exposure-safe.
- Vendor LOCAL PATCH #5 (fallback label contrast) and #6 (preferFlutterTier
  plumbing) remain: #5 fixes the pre-26 tier; #6 serves surfaces (§3) and any
  future opt-in.

## Sources
WWDC25 219 (Meet Liquid Glass), 284, 356; WWDC25 design-lab and UI-Frameworks
lab transcripts (samhenrigold gists); Apple HIG Materials; expo#44739
(segmented indicator glass at rest in lists); cupertino_native_better README;
flutter#46666 #40108 #103014 #107486; docs.flutter.dev iOS platform views.
