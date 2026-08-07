import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_viewmodel.dart';

/// Startup shell — router-outlet host for the `showcase_startup` leaf, same
/// shell+leaf pattern as `showcase_home_shell`. No chrome of its own: the
/// leaf (boot logic + loading UI) renders through the [NestedRouter].
class ShowcaseStartupShellView extends StackedView<ShowcaseStartupShellViewModel> {
  const ShowcaseStartupShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseStartupShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseStartupShellViewMobile(),
      tablet: (_) => const ShowcaseStartupShellViewTablet(),
      desktop: (_) => const ShowcaseStartupShellViewDesktop(),
    );
  }

  @override
  ShowcaseStartupShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseStartupShellViewModel();
}
