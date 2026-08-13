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

### 2. Controls — native OUTSIDE scrollables; Flutter tier INSIDE
**RULING REVERSED 2026-08-13** (user-ratified, on the clip-0813 probe trail:
A2 keep-alive negative, A1 reorder partial — see
`docs/plans/clip-0813-fix-plan.md`). The prior "native everywhere" ruling was
Apple-correct in design terms but unreachable in this embedding: any platform
view inside a Scrollable slices all later Flutter paint into overlay layers
whose rects ignore clip bounds (open engine #150646, no iOS escape hatch) —
dropped labels, stale white slabs, mis-bounded card fills, at any scroll
offset, for any content painted after the first platform view. The vendor
README's "DO NOT put platform views in scrolling lists" wins over visual
fidelity until the engine bug closes.

Mechanism: every control wrapper passes
`preferFlutterTier: Scrollable.maybeOf(context) != null` to its CN component —
the vendor's own Cupertino/Material fallback renders (with the PATCH #5/#7
label-contrast and tier-propagation fixes). Native platform views remain
everywhere OUTSIDE scrollables and in all chrome.

| Kit widget | In-scroll behavior |
|---|---|
| AppBoxKitNativeSegmentedControl | Flutter tier (CN fallback) |
| AppBoxKitNativeSwitch | Flutter tier |
| AppBoxKitNativeSlider / RangeSlider | Flutter tier |
| AppBoxKitNativeTextField | Flutter tier |
| AppBoxKitNativeSearchBar (in-form) | Flutter tier |
| AppBoxKitNativeButton | Flutter tier; **style-mapped** (below) |
| AppBoxKitNativeSplitButton | Flutter tier |
| AppBoxKitNativePopupMenu (in-content trigger) | Flutter tier |

**Button style mapping (in scroll content only):** `.glass`/`.glassProminent`
are opt-in styles Apple uses in chrome and branded moments (Apple Cash send
screen), not ordinary form CTAs. Inside a Scrollable the kit maps
`glass → tinted` and `prominentGlass → filled`, and the mapped style shapes
the Flutter-tier fallback's look. Outside scrollables styles pass through
unchanged on the native tier.

If glass controls must ever ride a scrollable again: re-run the auth-view
probe (see memory note) and re-check #150646 first — the same-day revert of
the ORIGINAL demotion predates this probe trail and is superseded by it.

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
4. **Fill color and foreground travel together in fallbacks.** Any fallback
   that sets a CupertinoButton `color` must set the foreground too: solid
   fill → contrasting color, translucent tint wash (glass) → the tint itself
   (vendor PATCH #5). The default foreground flips with `color` and lands
   tone-on-tone both ways (auth's blank Sign In; the profile toolbar's blank
   Share/Edit/Delete).

**Known residual (watch on device):** `AppBoxKitScrollEdgeEffect` drives a
partial-alpha Opacity over whatever crosses an edge band — post-allowlist
that child may host native controls, which puts a saveLayer over platform-view
slices (rule 1). No artifact is currently attributed to it on device; if edge
band label dropouts appear in a recording after the tab-stack clip landed,
this is the next suspect (fix direction: scrim-over instead of alpha-on).

**Deviation note — split button:** CNSplitButton renders via
CNGlassButtonGroup. If a non-glass group style exists it should map like
buttons; until then it stays native in content as an accepted deviation
(single showcase demo).

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
- Vendor LOCAL PATCH #5 (fallback label contrast) and #6 (preferFlutterTier
  plumbing) remain: #5 fixes the pre-26 tier; #6 serves surfaces (§3) and any
  future opt-in.

## Sources
WWDC25 219 (Meet Liquid Glass), 284, 356; WWDC25 design-lab and UI-Frameworks
lab transcripts (samhenrigold gists); Apple HIG Materials; expo#44739
(segmented indicator glass at rest in lists); cupertino_native_better README;
flutter#46666 #40108 #103014 #107486; docs.flutter.dev iOS platform views.
