import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

/// The Home-tab body: snackbar-variant smokes, the Glass CTA, the theme-mode
/// segmented demo, then the showcase's feedback tier (progress, loading,
/// split button) inside [AppBoxKitGlassCard]s. Scrollable so it fits under the
/// shared app bar.
class ShowcaseHomeView extends StackedView<ShowcaseHomeViewModel> {
  const ShowcaseHomeView({super.key});

  @override
  ShowcaseHomeViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseHomeViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseHomeViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseHomeViewMobile(),
      tablet: (_) => const ShowcaseHomeViewTablet(),
      desktop: (_) => const ShowcaseHomeViewDesktop(),
    );
  }
}
