/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The components surface. It renders kit components in their default
/// states for visual inspection.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_design_shell/spike_components/spike_components_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_components/spike_components_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_components/spike_components_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_components/spike_components_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_components/spike_components_viewmodel.dart';

class SpikeComponentsView extends StackedView<SpikeComponentsViewModel> {
  const SpikeComponentsView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.design',
    surfaceId: 'surface.design.components',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeComponentsViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeComponentsViewDesktop(),
      mobile: (_) => const SpikeComponentsViewMobile(),
      tablet: (_) => const SpikeComponentsViewTablet(),
    );
  }

  @override
  SpikeComponentsViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeComponentsViewModel();
}
