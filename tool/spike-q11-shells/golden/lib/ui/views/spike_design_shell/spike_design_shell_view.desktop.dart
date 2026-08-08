/// The views layer draws what the user sees and forwards the user's input.
/// A view-factor is one form factor's rendering of a single view; it shares
/// the view's viewmodel and owns no state.
///
/// The desktop rendering of design. It hosts the nested-router outlet the
/// leaf renders through.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_design_shell/spike_design_shell_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_design_shell_viewmodel.dart';

class SpikeDesignShellViewDesktop
    extends ViewModelWidget<SpikeDesignShellViewModel> {
  const SpikeDesignShellViewDesktop({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.design',
    surfaceId: 'surface.design.shell',
    anatomyNodeId: 'anatomy:shell.frame.desktop',
  );

  @override
  Widget build(BuildContext context, SpikeDesignShellViewModel viewModel) {
    return const NestedRouter();
  }
}
