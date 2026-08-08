/// The views layer draws what the user sees and forwards the user's input.
/// A view-factor is one form factor's rendering of a single view; it shares
/// the view's viewmodel and owns no state.
///
/// The mobile rendering of sign in.
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
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_auth_shell/spike_signin/spike_signin_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_spike_app/ui/views/spike_auth_shell/spike_signin/spike_signin_viewmodel.dart';

class SpikeSigninViewMobile
    extends ViewModelWidget<SpikeSigninViewModel> {
  const SpikeSigninViewMobile({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'screen.auth',
    surfaceId: 'surface.auth.signin',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget build(BuildContext context, SpikeSigninViewModel viewModel) {
    return const Scaffold(body: Center(child: Text('sign in')));
  }
}
