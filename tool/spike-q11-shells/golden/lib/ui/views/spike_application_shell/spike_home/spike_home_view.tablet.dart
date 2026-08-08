/// The views layer draws what the user sees and forwards the user's input.
/// A view-factor is one form factor's rendering of a single view; it shares
/// the view's viewmodel and owns no state.
///
/// The tablet rendering of home.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_application_shell/spike_home/spike_home_view.tablet.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_home/spike_home_viewmodel.dart';

class SpikeHomeViewTablet
    extends ViewModelWidget<SpikeHomeViewModel> {
  const SpikeHomeViewTablet({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.application',
    surfaceId: 'surface.application.home',
    anatomyNodeId: 'anatomy:view.body.tablet',
  );

  @override
  Widget build(BuildContext context, SpikeHomeViewModel viewModel) {
    return const Scaffold(body: Center(child: Text('home')));
  }
}
