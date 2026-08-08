/// The views layer draws what the user sees and forwards the user's input.
/// A view-factor is one form factor's rendering of a single view; it shares
/// the view's viewmodel and owns no state.
///
/// The mobile rendering of the splash surface. Brand mark only: no
/// navigation, no copy, no controls.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_startup_shell/spike_splashscreen/spike_splashscreen_viewmodel.dart';

class SpikeSplashscreenViewMobile
    extends ViewModelWidget<SpikeSplashscreenViewModel> {
  const SpikeSplashscreenViewMobile({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.startup',
    surfaceId: 'surface.startup.splashscreen',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget build(BuildContext context, SpikeSplashscreenViewModel viewModel) {
    return const Scaffold(body: Center(child: FlutterLogo(size: 96)));
  }
}
