import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';

class ShowcaseProfileViewMobile
    extends ViewModelWidget<ShowcaseProfileViewModel> {
  const ShowcaseProfileViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileViewModel viewModel) {
    return ListView(
      // Bottom = safe-area + tab-bar block so the last card can scroll
      // clear of the floating KitNativeTabBar — the shell extends the body
      // under it (extendBody) and previously the button laid out
      // unreachable beneath the bar.
      padding: EdgeInsets.fromLTRB(
          kSize16,
          kSize16,
          kSize16,
          kSize16 +
              MediaQuery.paddingOf(context).bottom +
              kShowcaseTabBarBlockHeight),
      children: [
        ShowcaseProfileRailCardWidget(viewModel: viewModel),
        verticalSpaceMedium,
        const ShowcaseSectionLabelWidget('Toolbar'),
        const ShowcaseProfileToolbarDemoWidget(),
        verticalSpaceMedium,
        const ShowcaseProfileFeedbackCardWidget(),
        verticalSpaceMedium,
        // Relative push within the profile tab's nested router —
        // the pushed route's animation drives the demo's
        // KitMotionScope (wake on push, scrubbed set-down on
        // iOS swipe-back).
        const ShowcaseProfileNavCardWidget(
          title: 'Motion',
          buttonLabel: 'Motion showcase',
          routeName: 'motion',
        ),
        verticalSpaceMedium,
        // appbox_kit_maps port — OpenStreetMap out of the box,
        // Mapbox tiles via --dart-define=MAPBOX_PUBLIC_TOKEN.
        const ShowcaseProfileNavCardWidget(
          title: 'Maps',
          buttonLabel: 'Maps showcase',
          routeName: 'maps',
        ),
        verticalSpaceMedium,
        // Video-parity sweep (ADR 0011): drawer, glass sheet,
        // dialog, input bar, grouped lists, chips, center toast.
        const ShowcaseProfileNavCardWidget(
          title: 'Components',
          buttonLabel: 'Components showcase',
          routeName: 'components',
        ),
      ],
    );
  }
}
