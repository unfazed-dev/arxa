import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_profile_shell_view.desktop.dart';
import 'showcase_profile_shell_view.tablet.dart';
import 'showcase_profile_shell_view.mobile.dart';
import 'showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellView
    extends StackedView<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseProfileShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseProfileShellViewMobile(),
      tablet: (_) => const ShowcaseProfileShellViewTablet(),
      desktop: (_) => const ShowcaseProfileShellViewDesktop(),
    );
  }

  @override
  ShowcaseProfileShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseProfileShellViewModel();
}
