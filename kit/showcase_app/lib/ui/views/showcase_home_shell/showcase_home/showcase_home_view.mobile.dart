/// The home tab's view. A view reads streams out and calls actions in — it
/// draws what the user sees and forwards the user's input; right now the tab's
/// viewmodel is a passive anchor, so the body renders from stateless demo
/// widgets directly.
///
/// This is the user interface for the home tab's root surface. It owns the
/// gallery chrome (chrome is per-surface, so this view carries it rather than
/// the shell) and lays out the demo widgets inside it — snackbar smokes, the
/// Glass CTA, the theme-mode toggle, and the feedback tier (progress, loading,
/// split button) — so the kit gallery can be browsed.
///
/// Requirements:
/// 1. [Home tab body] — shell-demos.home-and-application-shells.browse-the-home-shell
/// The home tab shows the kit's demo widgets so the gallery can be browsed.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │        home view         │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │      home viewmodel      │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No actions or streams yet — the body is stateless demo widgets.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home/showcase_home_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_home_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

class ShowcaseHomeViewMobile extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    // The chrome sits INSIDE this view now, so the list's `MediaQuery` must be
    // read below it: the glass tier's floating chrome raises `padding.top` for
    // its body subtree only, and reading it at this view's own context (above
    // the chrome) would tuck the first card under the bar. Same Builder shape
    // as showcase_components_view.mobile.dart.
    return ShowcaseGalleryChromeWidget(
      child: Builder(
        builder: (context) =>
            // Edge treatment owned by the list (see AppBoxKitEdgeAwareListView):
            // before this, only 2 of the 5 cards here carried
            // `.scrollEdgeEffect()`, so most of the home list slid under the tab
            // bar untreated. Top fade is auto-skipped by the wrapper under
            // extendBehindTopBar (cull boundary off-screen by construction).
            AppBoxKitEdgeAwareListView(
          bottomOcclusion: kShowcaseTabBarBlockHeight,
          // Materialization headroom (clip 13-53-b): a culled child re-enters
          // painting AT the boundary, and iOS 26 glass runs its materialize
          // animation on re-add — whichever row leads re-entry is visible
          // mid-animation. Overdraw moves the boundary above the physical top
          // so the animation finishes off-screen. Safe ONLY since the chrome
          // went native/full-bleed: the 13-32 regression was the opaque Flutter
          // bar failing to cover this region, and that bar no longer exists.
          extendBehindTopBar: true,
          // Trailing clearance matches the profile list: without it the last
          // card can never scroll clear of the floating tab bar, so its edge
          // effect would stay permanently engaged.
          // Top inset: 0 under the boxed app bar (Scaffold strips it); the
          // status-bar + floating-bar block on the glass tier, where the
          // gallery chrome lays this list full-bleed behind native floating
          // chrome.
          padding: EdgeInsets.fromLTRB(
              abxSize16,
              abxSize16 + MediaQuery.paddingOf(context).top,
              abxSize16,
              abxSize16 +
                  MediaQuery.paddingOf(context).bottom +
                  kShowcaseTabBarBlockHeight),
          children: [
            const Center(
              child: Text(
                'Kit Showcase',
                style: TextStyle(
                    fontSize: abxFontXXXLarge, fontWeight: FontWeight.w900),
              ),
            ),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSnackbarSmokeRowWidget(),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseGlassCtaButtonWidget(),
            appBoxKitVerticalSpaceMedium,
            // Native segmented control that drives AppBoxKitThemeService's theme
            // mode — proves the kit theme is wired end-to-end (see swatch below).
            const ShowcaseThemeModeSegmentedDemoWidget(),
            appBoxKitVerticalSpaceLarge,

            // --- Showcase: feedback tier (progress / loading / split button) ---
            const ShowcaseProgressLoadingCardWidget(),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSplitButtonCardWidget(),
          ],
        ),
      ),
    );
  }
}
