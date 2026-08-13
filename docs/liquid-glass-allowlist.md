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
| AppBoxKitNativeAppBar / SliverAppBar | Flutter-drawn; on the GLASS TIER the gallery replaces it with AppBoxKitNativeFloatingBar (see rule 4 ruling) |
| AppBoxKitNativeFloatingBar | Native glass floating top chrome (glass tier) — title capsule + native actions over a full-bleed body; the top-edge counterpart of the tab bar |

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
   Second fix (`extendBehindTopBar`, fd5f4422): oversize the viewport
   upward (OverflowBox, bottom-aligned; overdraw returned as top padding)
   so culling happens off-screen like the bottom edge — REGRESSED, see
   counter-evidence below; reverted at the gallery call sites.
   `Scaffold.extendBodyBehindAppBar` was rejected twice: the gallery body
   hosts nested-route Scaffolds whose own bars would inherit the inset
   shift.
   Corroboration (engine source, 2026-08-13): an unpainted platform view is
   `removeFromSuperview`'d entirely (FlutterPlatformViewsController.mm
   ~:1011) and re-added via `addSubview:` on re-entry — so a cull kills the
   WHOLE view, label included. Discriminator vs the fade signature: label
   survives + direction asymmetry = scroll demotion (no geometry fix helps);
   whole view pops = cull (this rule applies). That iOS 26 glass replays its
   materialization on re-add is device-observed inference — no Apple source
   states it.
   **Counter-evidence (clip 13-32): the overdraw fix REGRESSED.** With
   platform views painting behind the Flutter bar, overlay-layer churn
   flashed body content OVER the bar during fast scrolls — the flutter#86787
   class the research pass flagged as watch-item. Overdraw reverted at the
   gallery call sites the same day. Standing conclusion after three
   mechanisms (edge-effect alpha, Clip.none, viewport overdraw): a
   Flutter-drawn opaque bar cannot reliably cover platform views passing
   behind it (paint order does not survive hybrid-composition slicing), and
   culling them at the seam shimmers. The robust arrangements are (a)
   native top chrome — UIView-over-UIView z-order, the reason the bottom
   tab bar is clean — or (b) no platform views in the scrolling content
   under the bar. Direction is a product ruling, not a patch.
   **Ruling (2026-08-13, user-ratified): native top bar.** The gallery
   chrome now branches: glass tier = `AppBoxKitNativeFloatingBar` (frosted
   Flutter title pill per rule 5 + the existing native action buttons)
   floating over a FULL-BLEED body, so content culls at the physical
   screen edge; other tiers keep the boxed Flutter bar. Nested-route
   Scaffolds inset via the chrome's raised MediaQuery top padding,
   unmodified. Plan: docs/plans/native-top-bar.md.
   **Residual + fix (clip 13-53-b):** re-add at the boundary is
   TIME-based — the culled smoke block's bottom row re-entered the screen
   mid-materialization (identical widgets to the clean top row; the only
   difference was leading re-entry). Fix: `extendBehindTopBar` overdraw is
   BACK ON for the gallery lists — now safe because the overdraw region is
   off-screen above a native/full-bleed chrome (the 13-32 flash needed the
   opaque Flutter bar, which no longer exists). The boundary sits ~120px
   above the physical top, buying the animation time to finish unseen.
5. **No native glass may overhang a path scrolled native glass travels
   (clip 13-53).** With the floating native bar, the home smoke row's
   compose button washed to a square ghost for EXACTLY the title capsule's
   span while crossing it — glass-on-glass stacking — and buttons crossing
   the pill gaps stayed crisp (the discriminating observation). Apple's
   "don't stack glass" applies across our chrome/content split: fixed
   chrome elements that scrolled glass passes under must be Flutter-drawn
   (AppBoxKitFrostedSurface platformViewSafe) — so the floating bar's
   TITLE pill is deliberately not native. Interactive bar controls stay
   native glass; if partial overlaps (warning icon under the search
   button) ever artifact, widen the pill gaps before demoting anything.
   Pinned by appbox_kit_native_floating_bar_test.
6. **Fill color and foreground travel together in fallbacks.** Any fallback
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
