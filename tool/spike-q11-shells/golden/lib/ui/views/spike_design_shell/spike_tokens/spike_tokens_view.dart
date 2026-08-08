/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The tokens surface. It renders the active token set so the values can be
/// inspected against the design.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_design_shell/spike_tokens/spike_tokens_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_tokens/spike_tokens_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_tokens/spike_tokens_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_tokens/spike_tokens_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_design_shell/spike_tokens/spike_tokens_viewmodel.dart';

class SpikeTokensView extends StackedView<SpikeTokensViewModel> {
  const SpikeTokensView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.design',
    surfaceId: 'surface.design.tokens',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeTokensViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeTokensViewDesktop(),
      mobile: (_) => const SpikeTokensViewMobile(),
      tablet: (_) => const SpikeTokensViewTablet(),
    );
  }

  @override
  SpikeTokensViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeTokensViewModel();
}
