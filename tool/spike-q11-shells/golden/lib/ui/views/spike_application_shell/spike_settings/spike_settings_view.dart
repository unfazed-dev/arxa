/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The settings surface. It presents account and preference controls for
/// the signed-in user.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_application_shell/spike_settings/spike_settings_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/app/inspect_attrs.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_settings/spike_settings_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_settings/spike_settings_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_settings/spike_settings_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_application_shell/spike_settings/spike_settings_viewmodel.dart';

class SpikeSettingsView extends StackedView<SpikeSettingsViewModel> {
  const SpikeSettingsView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const InspectAttrs inspectAttrs = InspectAttrs(
    screenId: 'screen.application',
    surfaceId: 'surface.application.settings',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeSettingsViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeSettingsViewDesktop(),
      mobile: (_) => const SpikeSettingsViewMobile(),
      tablet: (_) => const SpikeSettingsViewTablet(),
    );
  }

  @override
  SpikeSettingsViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeSettingsViewModel();
}
