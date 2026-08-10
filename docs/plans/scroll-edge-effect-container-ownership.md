# Scroll edge effect — container ownership + tier-gated blur

Status: **landed**. Two user-approved decisions, both implemented and green.

## The instrument was broken first

`kit/showcase_app/test/slowness_measurement_test.dart` declared `platformViewBackedTypes`
containing `'CNLiquidGlassContainer'`. **No such class exists.** The vendor names it
`LiquidGlassContainer` (`liquid_glass_container.dart:17`), and it is exactly what
`AppBoxKitGlassCard` builds on the iOS 26 tier (`appbox_kit_glass_card.dart:66-77`).

So the set matched nothing for every glass card, and the previous session's numbers —
reported to the user as verified — were wrong in the direction of "nothing to see here":

| Claim (previous session) | Corrected |
|---|---|
| 0 platform views under the notes-list blur | **4**, on **200 of 200** scroll frames |
| 14 platform views on the iOS 26 boot path | **15** (`LiquidGlassContainer: 2` was invisible) |

The other 14 names in the set are real and map 1:1 onto the vendor files containing a
`UiKitView(` call. One name, one blind spot.

**Harness ceiling, stated:** `LiquidGlassContainer.build` gates on the *vendor's*
`PlatformVersion.supportsLiquidGlass`, which resolves through `dart:io`
`Platform.isIOS` (`version_detector.dart:143,149`) — false headlessly regardless of
`AppBoxKitPlatform.override`. So it returns `widget.child` in tests and **no `UiKitView`
is ever instantiated**. The counts above are "widgets that become `UiKitView`s on
device", which is the best available headless proxy, not live platform views.

## Defect 1 — the effect was opt-in, and 11 of 18 call sites forgot

`.scrollEdgeEffect()` is per-call-site sugar. Census at the time of writing:

| | count |
|---|---|
| Glass-bearing showcase widgets **with** the effect | 7 |
| Glass-bearing showcase widgets **without** it | 11 |
| Profile tree specifically | 3 with, **8 without** |

The visible case: `showcase_profile_view.mobile.dart:69` placed a bare
`AppBoxKitNativeToolbar` (`CNGlassButtonGroup` — a platform view on iOS 26) directly in
the `ListView`, sandwiched between two treated cards. On scroll the cards faded under the
tab bar and the toolbar stayed crisp at full alpha. `showcase_profile_rail_card_widget.dart:96`
rationalised it — *"Cards only: the bare toolbar/labels are chrome, not content"* — but it
is inside the list, it scrolls, it is content. A leaf cannot detect that a sibling was
forgotten; a container cannot miss a child.

**Fix:** `AppBoxKitEdgeAwareListView` (`kit/ui_library/lib/widgets/appbox_kit_edge_aware_list_view.dart`)
wraps every child, spacers included, so the rule has no exceptions to remember.

Edges stay opt-in on purpose. An edge effect with no chrome on that edge is *wrong*, not
redundant — it fades content out just before the viewport clips it:

- `topEdge` — only for chrome pinned **inside** the scrollable. Default `false`.
- `bottomOcclusion` — height of chrome stacked **over** the scrollable from outside.
  `null` (default) = nothing overlays the bottom.

### Verified non-defect

The profile list has no top-edge effect, and that is correct. `ShowcaseGalleryChromeWidget`
uses an opaque `Scaffold.appBar` with **no** `extendBodyBehindAppBar`, so content never
underlaps it. Notes needs a top edge only because it has a pinned sliver search header
*inside* its `CustomScrollView`. This was nearly filed as a bug.

### Also verified, also not a defect

The chrome gate is **already** consolidated: 14 kit widgets call `.chromeGated()`
internally, and every widget with vendor CN refs has it (`cnrefs == 0 ⟺ gated == 0`, no
gaps). Showcase code correctly calls it nowhere. An earlier grep for `NativeChromeGate`
missed this because the wiring uses the `.chromeGated()` extension.

## Defect 2 — the blur reached the text but never the glass

`AppBoxKitScrollEdgeEffect`'s blur is an `ImageFilterLayer`, which filters **Flutter's
painted output**. On the Liquid Glass tier the card's surface is a platform view
composited natively, so the filter reached the card's *text* and not the slab under it:
softening labels on a crisp slab, mid-crossing. Opacity is the mutator iOS hybrid
composition applies to platform views reliably (`appbox_kit_native_chrome_gate.dart`).

**Fix:** blur is frosted-tier only. Driven to `sigma = 0` rather than branched, because
the wrapper chain must keep a constant node count — that invariant is what stops a
platform view being unmounted at threshold crossings, and `_EdgeEffectBlur` at sigma 0
already paints its child directly with no layer. One-line change plus docs.

**What is proven vs inferred.** Proven headlessly: no `ImageFilterLayer` is pushed on the
glass tier while the fade is engaged, with a frosted-tier control proving the assertion
is not vacuous. Inferred, not measured: that the removed filter layer was costing
embedder overlay recomposition per frame. The correctness argument stands alone.

## Results

| | before | after |
|---|---|---|
| Effects on the home list | 2 | **11** (one per child) |
| Effects owned by notes folder | 13 | 13 (untouched) |
| Elements at boot, iOS 26 tiers | 756 | **802** (+46, the wrapper cost) |
| Top-level platform views at boot | 15 | 15 |
| `kit/ui_library` | 273 / 273 | **281 / 281** |
| `kit/showcase_app` | 119 / 119 | **119 / 119** |

`analyze` clean in both. The +46 elements is the honest price of complete coverage.

**M5's "4 platform views under a LIVE blur" is unchanged by design** — that probe keys on
`Opacity < 1`, not on the filter layer, so it cannot see defect 2 either way. The tier
change is pinned by `appbox_kit_scroll_edge_effect_tier_test.dart`, which keys on
`ImageFilterLayer` directly.

## Scope left alone, explicitly

- **Notes folder is NOT converted.** It is a `CustomScrollView`; the container is for the
  box-child case. The leaf sugar stays public because slivers still need it. Notes does
  benefit from defect 2's fix, which is tier-wide.
- **The tablet/desktop variants** of all three views are stubs and were not touched.

## Needs a device

Both changes alter iOS 26 rendering and neither can be confirmed headlessly:

1. Cards now fade as one surface instead of blurring their text over a crisp slab.
2. Whether removing the filter layer over glass-backed subtrees measurably improves
   scroll smoothness — the inferred half above.
