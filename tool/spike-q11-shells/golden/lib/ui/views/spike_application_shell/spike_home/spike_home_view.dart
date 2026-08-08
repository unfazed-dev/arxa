/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The home surface. It is the first authenticated surface a signed-in user
/// lands on.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_application_shell/spike_home/spike_home_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_home/spike_home_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_home/spike_home_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_home/spike_home_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_home/spike_home_viewmodel.dart';

class SpikeHomeView extends StackedView<SpikeHomeViewModel> {
  const SpikeHomeView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.application',
    surfaceId: 'surface.application.home',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeHomeViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeHomeViewDesktop(),
      mobile: (_) => const SpikeHomeViewMobile(),
      tablet: (_) => const SpikeHomeViewTablet(),
    );
  }

  @override
  SpikeHomeViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeHomeViewModel();
}
