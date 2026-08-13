# Native top bar for the gallery chrome (ratified 2026-08-13)

## Why (three failed mechanisms → architecture ruling)

Native glass controls scrolling past the Flutter-drawn opaque app bar are
broken in both possible arrangements:

- culled at the bar seam → visible pop/shimmer (clips 12-48, 13-17);
- painted behind the bar (viewport overdraw, fd5f4422) → overlay-layer churn
  flashes body content OVER the bar during fast scrolls (clip 13-32,
  flutter#86787 class).

The bottom edge is clean because the tab bar is NATIVE: UIView-over-UIView
z-order is deterministic and platform views transit behind it composited.
User ruling (AskUserQuestion, 2026-08-13): rebuild the gallery top bar as
native chrome. See docs/liquid-glass-allowlist.md rule 4 for the evidence
trail.

## Design

Glass tier (iOS 26) only; every other tier keeps today's `Scaffold.appBar`.

1. **Kit widget `AppBoxKitNativeFloatingBar`** — a floating bar row inside
   `SafeArea`: title in a native glass capsule (`LiquidGlassContainer`,
   vendor: native glass UIView background + Flutter child on top) and the
   existing native glass action buttons. Block height constant
   `kAppBoxKitFloatingBarBlockHeight = 44 + abxGap8`. Because the bar is the
   LAST thing painted, its platform view composites above every platform
   view in the scrolled content — the tab-bar lifecycle, applied to the top.
2. **Gallery chrome branches on `AppBoxKitPlatform.supportsLiquidGlass`**:
   glass tier = `Scaffold(appBar: null)` + `Stack[full-bleed child,
   floating bar]`, with the child's `MediaQuery.padding.top` raised by the
   bar block so nested-route Scaffolds (components/motion/maps) inset
   themselves correctly without modification; other tiers unchanged.
3. **Tab-root lists** add `MediaQuery.paddingOf(context).top` to their
   explicit top padding (explicit `ListView.padding` ignores MediaQuery).
   On non-glass tiers the Scaffold has an appBar, so that value is 0 and
   nothing changes; on the glass tier it clears the floating bar. The
   viewport's leading edge now sits at the physical top, so platform views
   cull off-screen — the actual fix for the seam pop.

Residual accepted: content scrolls behind the status bar and under the
glass pills (that is the iOS 26 design language, same as the bottom tab
pill); worst-case overlay churn can blink the Flutter-drawn title text for
a frame, but content can no longer garble with bar chrome.

## Steps

1. Kit: `appbox_kit_native_floating_bar.dart` + barrel export + widget test.
2. Showcase: tier branch in `showcase_gallery_chrome_widget.dart`.
3. Showcase: top-padding change in home/search/profile mobile views.
4. Docs: allowlist §1 + rule 4 addendum; this plan.
5. Suites green; device verification: scroll all three tabs past the bar,
   fast flicks and slow half-hidden creeps; pushed routes unchanged.
