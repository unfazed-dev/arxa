/// The unknown shell's view (route `/showcase/unknown`). A view is actions in,
/// streams out: the user taps and the viewmodel acts; a value changes and the
/// view redraws the part listening to it.
///
/// This is the user interface for the screen shown when a route doesn't match.
/// It is a router-outlet host — no chrome of its own, just a nested router that
/// mounts the unknown leaf. The desktop, tablet, and mobile variants each
/// delegate to that same outlet.
///
/// Requirements:
/// 1. [Bad-route host] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The shell hosts the unknown leaf through a nested router.
///
/// Relationships:
///
///          ┌─────────────────────┐
///          │ unknown shell view  │
///          └─────────────────────┘
///       ┌──────────────────────────┐
///       │ unknown shell viewmodel  │
///       └──────────────────────────┘
///        ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_viewmodel.dart';

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
