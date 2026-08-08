/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The splash surface. Brand logo only: no navigation, no copy, no
/// controls. It is a surface, never a shell.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_viewmodel.dart';

class SpikeSplashscreenView extends StackedView<SpikeSplashscreenViewModel> {
  const SpikeSplashscreenView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.startup',
    surfaceId: 'surface.startup.splashscreen',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeSplashscreenViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeSplashscreenViewDesktop(),
      mobile: (_) => const SpikeSplashscreenViewMobile(),
      tablet: (_) => const SpikeSplashscreenViewTablet(),
    );
  }

  @override
  SpikeSplashscreenViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeSplashscreenViewModel();
}
