import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_home_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

class ShowcaseHomeViewMobile extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize16),
      children: [
        const Center(
          child: Text(
            'Kit Showcase',
            style:
                TextStyle(fontSize: kFontXXXLarge, fontWeight: FontWeight.w900),
          ),
        ),
        verticalSpaceMedium,
        const ShowcaseSnackbarSmokeRowWidget(),
        verticalSpaceMedium,
        const ShowcaseGlassCtaButtonWidget(),
        verticalSpaceMedium,
        // Native segmented control that drives KitThemeService's theme mode
        // — proves the kit theme is wired end-to-end (see swatch below).
        const ShowcaseThemeModeSegmentedDemoWidget(),
        verticalSpaceLarge,

        // --- Showcase: feedback tier (progress / loading / split button) ---
        const ShowcaseProgressLoadingCardWidget(),
        verticalSpaceMedium,
        const ShowcaseSplitButtonCardWidget(),
      ],
    );
  }
}
