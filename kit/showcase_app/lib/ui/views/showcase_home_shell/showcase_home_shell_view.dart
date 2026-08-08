/// The home shell's view. A view reads streams out and calls actions in — it
/// draws what the user sees and forwards the user's input; right now the
/// shell's viewmodel is a passive anchor, so there is nothing to call or read
/// yet.
///
/// This is the user interface for the home shell's outer frame. It wraps a
/// nested router in the gallery chrome so the home tab renders inside.
///
/// Requirements:
/// 1. [Home shell frame] — shell-demos.home-and-application-shells.browse-the-home-shell
/// The shell wraps a nested router in the gallery chrome so the home tab renders inside.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │     home shell view      │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │   home shell viewmodel   │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No actions or streams yet — the viewmodel is a passive anchor.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellView extends StackedView<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'showcase.home',
    surfaceId: 'surface.home.shell',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseHomeShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseHomeShellViewMobile(),
      tablet: (_) => const ShowcaseHomeShellViewTablet(),
      desktop: (_) => const ShowcaseHomeShellViewDesktop(),
    );
  }

  @override
  ShowcaseHomeShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseHomeShellViewModel();
}
