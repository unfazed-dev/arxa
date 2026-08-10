/// The home tab's view. A view reads streams out and calls actions in — it
/// draws what the user sees and forwards the user's input; right now the tab's
/// viewmodel is a passive anchor, so the body renders from stateless demo
/// widgets directly.
///
/// This is the user interface for the home tab's body. It lays out the demo
/// widgets — snackbar smokes, the Glass CTA, the theme-mode toggle, and the
/// feedback tier (progress, loading, split button) — so the kit gallery can be
/// browsed.
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
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_home_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

class ShowcaseHomeViewMobile extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    // Edge treatment owned by the list (see AppBoxKitEdgeAwareListView): before
    // this, only 2 of the 5 cards here carried `.scrollEdgeEffect()`, so most of
    // the home list slid under the tab bar untreated. No topEdge — the gallery
    // chrome's app bar is opaque and does not extend behind.
    return AppBoxKitEdgeAwareListView(
      bottomOcclusion: kShowcaseTabBarBlockHeight,
      // Trailing clearance matches the profile list: without it the last card
      // can never scroll clear of the floating tab bar, so its edge effect
      // would stay permanently engaged.
      padding: EdgeInsets.fromLTRB(
          abxSize16,
          abxSize16,
          abxSize16,
          abxSize16 +
              MediaQuery.paddingOf(context).bottom +
              kShowcaseTabBarBlockHeight),
      children: [
        const Center(
          child: Text(
            'Kit Showcase',
            style:
                TextStyle(fontSize: abxFontXXXLarge, fontWeight: FontWeight.w900),
          ),
        ),
        appBoxKitVerticalSpaceMedium,
        const ShowcaseSnackbarSmokeRowWidget(),
        appBoxKitVerticalSpaceMedium,
        const ShowcaseGlassCtaButtonWidget(),
        appBoxKitVerticalSpaceMedium,
        // Native segmented control that drives AppBoxKitThemeService's theme mode
        // — proves the kit theme is wired end-to-end (see swatch below).
        const ShowcaseThemeModeSegmentedDemoWidget(),
        appBoxKitVerticalSpaceLarge,

        // --- Showcase: feedback tier (progress / loading / split button) ---
        const ShowcaseProgressLoadingCardWidget(),
        appBoxKitVerticalSpaceMedium,
        const ShowcaseSplitButtonCardWidget(),
      ],
    );
  }
}
