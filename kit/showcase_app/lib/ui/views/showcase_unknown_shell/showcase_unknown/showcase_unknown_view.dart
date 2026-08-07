/// The unknown leaf's view (route `/showcase/unknown`, nested under the unknown
/// shell). A view is actions in, streams out.
///
/// This is the user interface for the dead-end screen a bad route lands on.
/// It renders the static unknown body through the desktop, tablet, and mobile
/// variants.
///
/// Requirements:
/// 1. [Dead-end body] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The leaf renders a body so the unknown route is not a blank screen.
///
/// Relationships:
///
///          ┌────────────────────┐
///          │ unknown leaf view  │
///          └────────────────────┘
///       ┌─────────────────────────┐
///       │ unknown leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

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
