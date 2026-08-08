/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The auth shell's outer frame. It holds a nested-router outlet that each
/// credential surface renders through.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_auth_shell/spike_auth_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_auth_shell_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_auth_shell_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_auth_shell_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_auth_shell_viewmodel.dart';

class SpikeAuthShellView extends StackedView<SpikeAuthShellViewModel> {
  const SpikeAuthShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.auth',
    surfaceId: 'surface.auth.shell',
    anatomyNodeId: 'anatomy:shell.frame',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeAuthShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeAuthShellViewDesktop(),
      mobile: (_) => const SpikeAuthShellViewMobile(),
      tablet: (_) => const SpikeAuthShellViewTablet(),
    );
  }

  @override
  SpikeAuthShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeAuthShellViewModel();
}
