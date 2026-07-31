import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_profile_view.desktop.dart';
import 'showcase_profile_view.tablet.dart';
import 'showcase_profile_view.mobile.dart';
import 'showcase_profile_viewmodel.dart';

/// Profile-tab showcase: [KitNativeNavigationRail], [KitNativeToolbar],
/// and the two imperative surfaces —
/// [KitNotificationService] + the stacked [BottomSheetService] (backed by
/// KitBottomSheetService → kitShowNativeSheet) — wired to buttons.
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
