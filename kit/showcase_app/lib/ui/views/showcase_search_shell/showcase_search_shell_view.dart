import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_search_shell_view.desktop.dart';
import 'showcase_search_shell_view.tablet.dart';
import 'showcase_search_shell_view.mobile.dart';
import 'showcase_search_shell_viewmodel.dart';

class ShowcaseSearchShellView
    extends StackedView<ShowcaseSearchShellViewModel> {
  const ShowcaseSearchShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseSearchShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseSearchShellViewMobile(),
      tablet: (_) => const ShowcaseSearchShellViewTablet(),
      desktop: (_) => const ShowcaseSearchShellViewDesktop(),
    );
  }

  @override
  ShowcaseSearchShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseSearchShellViewModel();
}
