import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

/// appbox_kit_motion showcase — route-driven wake/set-down choreography
/// (KitMotionScope + KitWake), spec presets, manual replay, and the
/// flutter_animate adapter, on one pushed surface so the route push/pop
/// (and iOS swipe-back scrub) *is* the demo driver.
class ShowcaseMotionView extends StackedView<ShowcaseMotionViewModel> {
  const ShowcaseMotionView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseMotionViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseMotionViewMobile(),
      tablet: (_) => const ShowcaseMotionViewTablet(),
      desktop: (_) => const ShowcaseMotionViewDesktop(),
    );
  }

  @override
  ShowcaseMotionViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseMotionViewModel();
}
