/// The views layer draws what the user sees and forwards the user's input.
/// A view reads streams out and calls actions in; it holds no business
/// logic of its own.
///
/// The sign-in surface. It captures an existing credential and forwards it
/// to the session facade.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_auth_shell/spike_signin/spike_signin_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_signin/spike_signin_view.desktop.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_signin/spike_signin_view.mobile.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_signin/spike_signin_view.tablet.dart';
import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_signin/spike_signin_viewmodel.dart';

class SpikeSigninView extends StackedView<SpikeSigninViewModel> {
  const SpikeSigninView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.auth',
    surfaceId: 'surface.auth.signin',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    SpikeSigninViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      desktop: (_) => const SpikeSigninViewDesktop(),
      mobile: (_) => const SpikeSigninViewMobile(),
      tablet: (_) => const SpikeSigninViewTablet(),
    );
  }

  @override
  SpikeSigninViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      SpikeSigninViewModel();
}
