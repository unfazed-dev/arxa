/// The startup shell's view. A view reads streams out and calls actions in —
/// it draws what the user sees and forwards the user's input; right now the
/// shell's viewmodel is a passive anchor, so there is nothing to call or read
/// yet.
///
/// This is the user interface for the startup shell's outer frame. It holds a
/// nested-router outlet that the startup leaf (boot logic + loading UI)
/// renders through.
///
/// Requirements:
/// 1. [Shell host]
/// The shell holds a nested-router outlet for the startup leaf.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │    startup shell view    │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │ startup shell viewmodel  │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No actions or streams yet — the viewmodel is a passive anchor.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_startup_shell/showcase_startup_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_viewmodel.dart';

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
