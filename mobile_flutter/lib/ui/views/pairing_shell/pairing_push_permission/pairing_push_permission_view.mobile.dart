// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       pairing_shell_push_permission_view
//   comp:          PairingPushPermissionViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'pairing_push_permission_viewmodel.dart';

class PairingPushPermissionViewMobile
    extends ViewModelWidget<PairingPushPermissionViewModel> {
  const PairingPushPermissionViewMobile({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
    body: Center(child: Text('pairing.push_permission · mobile')),
  );
}
