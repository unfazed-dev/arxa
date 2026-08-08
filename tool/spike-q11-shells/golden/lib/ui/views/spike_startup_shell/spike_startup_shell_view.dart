/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The startup shell's outer frame. It holds a nested-router outlet that
/// the startup leaf (boot logic + loading UI) renders through.
///
/// Requirements:
/// 1. [Placeholder]
/// PLACEHOLDER(builder): the requirements body is user-owned. The
/// scaffolder emits the section and this marker only.
///
/// Relationships:
///
/// PLACEHOLDER(builder): the relationships diagram is user-owned.
/// The scaffolder emits the section and this marker only.
///
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_startup_shell/spike_startup_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_startup_shell_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_startup_shell_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_startup_shell_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_startup_shell_viewmodel.dart';

class SpikeStartupShellView extends StackedView<SpikeStartupShellViewModel> {
  const SpikeStartupShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.startup',
    surfaceId: 'surface.startup.shell',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeStartupShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeStartupShellViewDesktop(),
      mobile: (_) => const SpikeStartupShellViewMobile(),
      tablet: (_) => const SpikeStartupShellViewTablet(),
    );
  }

  @override
  SpikeStartupShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeStartupShellViewModel();
}
