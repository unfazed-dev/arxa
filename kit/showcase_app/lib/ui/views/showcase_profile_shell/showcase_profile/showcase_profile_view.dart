import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';

/// Profile-tab showcase: [AppBoxKitNativeNavigationRail], [AppBoxKitNativeToolbar],
/// and the two imperative surfaces —
/// [AppBoxKitNotificationService] + the stacked [BottomSheetService] (backed by
/// AppBoxKitBottomSheetService → appBoxKitShowNativeSheet) — wired to buttons.
class ShowcaseProfileView extends StackedView<ShowcaseProfileViewModel> {
  const ShowcaseProfileView({super.key});

  @override
  ShowcaseProfileViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseProfileViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseProfileViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseProfileViewMobile(),
      tablet: (_) => const ShowcaseProfileViewTablet(),
      desktop: (_) => const ShowcaseProfileViewDesktop(),
    );
  }
}
