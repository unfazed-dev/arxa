import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_viewmodel.dart';

class ShowcaseUnknownView extends StackedView<ShowcaseUnknownViewModel> {
  const ShowcaseUnknownView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseUnknownViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseUnknownViewMobile(),
      tablet: (_) => const ShowcaseUnknownViewTablet(),
      desktop: (_) => const ShowcaseUnknownViewDesktop(),
    );
  }

  @override
  ShowcaseUnknownViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseUnknownViewModel();
}
