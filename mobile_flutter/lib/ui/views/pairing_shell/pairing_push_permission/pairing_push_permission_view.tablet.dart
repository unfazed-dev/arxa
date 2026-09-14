// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       pairing_shell_push_permission_view
//   comp:          PairingPushPermissionViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'pairing_push_permission_viewmodel.dart';

class PairingPushPermissionViewTablet
    extends ViewModelWidget<PairingPushPermissionViewModel> {
  const PairingPushPermissionViewTablet({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
    body: Center(child: Text('pairing.push_permission · tablet')),
  );
}
