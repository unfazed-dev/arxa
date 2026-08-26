/// The startup leaf's view. A view reads streams out and calls actions in —
/// it draws what the user sees and forwards the user's input; here the one
/// input is telling the viewmodel to boot once the view is ready.
///
/// This is the user interface for the startup leaf. It shows a loading
/// indicator while the app boots and kicks the boot off as soon as it is
/// ready.
///
/// Requirements:
/// 1. [Boot trigger] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// Once the view is ready, it tells the viewmodel to run the boot logic.
/// 2. [Loading screen] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// While boot runs, a loading indicator is shown.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │       startup view       │
///   └──────────────────────────┘
///   ACT ▼
///   [1]
///   ┌──────────────────────────┐
///   │    startup viewmodel     │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
///  actions (ACT)
///    1. runStartupLogic
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.desktop.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.tablet.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.mobile.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_viewmodel.dart';

class ShowcaseStartupView extends StackedView<ShowcaseStartupViewModel> {
  const ShowcaseStartupView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const ArxaKitInspectAttrs inspectAttrs = ArxaKitInspectAttrs(
    screenId: 'showcase.startup',
    surfaceId: 'surface.startup.startup',
    anatomyNodeId: 'anatomy:view.body',
  );

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
