/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The not-found surface. It explains that the requested route does not
/// resolve and offers the way back.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_viewmodel.dart';

class SpikeNotfoundView extends StackedView<SpikeNotfoundViewModel> {
  const SpikeNotfoundView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.unknown',
    surfaceId: 'surface.unknown.notfound',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeNotfoundViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeNotfoundViewDesktop(),
      mobile: (_) => const SpikeNotfoundViewMobile(),
      tablet: (_) => const SpikeNotfoundViewTablet(),
    );
  }

  @override
  SpikeNotfoundViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeNotfoundViewModel();
}
