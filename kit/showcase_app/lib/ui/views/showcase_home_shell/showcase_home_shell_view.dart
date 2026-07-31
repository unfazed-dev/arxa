import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_home_shell_view.desktop.dart';
import 'showcase_home_shell_view.tablet.dart';
import 'showcase_home_shell_view.mobile.dart';
import 'showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellView extends StackedView<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseHomeShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseHomeShellViewMobile(),
      tablet: (_) => const ShowcaseHomeShellViewTablet(),
      desktop: (_) => const ShowcaseHomeShellViewDesktop(),
    );
  }

  @override
  ShowcaseHomeShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseHomeShellViewModel();
}
