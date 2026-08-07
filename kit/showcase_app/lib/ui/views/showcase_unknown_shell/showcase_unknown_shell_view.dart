import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_viewmodel.dart';

/// Unknown (404) shell — router-outlet host for the `showcase_unknown` leaf,
/// same shell+leaf pattern as `showcase_home_shell`. No chrome of its own:
/// the leaf renders through the [NestedRouter].
class ShowcaseUnknownShellView extends StackedView<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseUnknownShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseUnknownShellViewMobile(),
      tablet: (_) => const ShowcaseUnknownShellViewTablet(),
      desktop: (_) => const ShowcaseUnknownShellViewDesktop(),
    );
  }

  @override
  ShowcaseUnknownShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseUnknownShellViewModel();
}
