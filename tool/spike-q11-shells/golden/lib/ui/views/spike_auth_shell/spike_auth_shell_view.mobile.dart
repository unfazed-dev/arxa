/// The views layer draws what the user sees and forwards the user's input.
/// A view-factor is one form factor's rendering of a single view; it shares
/// the view's viewmodel and owns no state.
///
/// The mobile rendering of auth. It hosts the nested-router outlet the leaf
/// renders through.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_auth_shell/spike_auth_shell_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_auth_shell_viewmodel.dart';

class SpikeAuthShellViewMobile
    extends ViewModelWidget<SpikeAuthShellViewModel> {
  const SpikeAuthShellViewMobile({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.auth',
    surfaceId: 'surface.auth.shell',
    anatomyNodeId: 'anatomy:shell.frame.mobile',
  );

  @override
  Widget build(BuildContext context, SpikeAuthShellViewModel viewModel) {
    return const NestedRouter();
  }
}
