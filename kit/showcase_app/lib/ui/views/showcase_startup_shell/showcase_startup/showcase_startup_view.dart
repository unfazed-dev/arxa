import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_startup_view.desktop.dart';
import 'showcase_startup_view.tablet.dart';
import 'showcase_startup_view.mobile.dart';
import 'showcase_startup_viewmodel.dart';

class ShowcaseStartupView extends StackedView<ShowcaseStartupViewModel> {
  const ShowcaseStartupView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseStartupViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseStartupViewMobile(),
      tablet: (_) => const ShowcaseStartupViewTablet(),
      desktop: (_) => const ShowcaseStartupViewDesktop(),
    );
  }

  @override
  ShowcaseStartupViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseStartupViewModel();

  @override
  void onViewModelReady(ShowcaseStartupViewModel viewModel) =>
      SchedulerBinding.instance
          .addPostFrameCallback((timeStamp) => viewModel.runStartupLogic());
}
