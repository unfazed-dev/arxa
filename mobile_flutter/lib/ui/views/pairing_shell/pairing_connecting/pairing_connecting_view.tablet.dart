// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       pairing_shell_connecting_view
//   comp:          PairingConnectingViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'pairing_connecting_viewmodel.dart';

class PairingConnectingViewTablet
    extends ViewModelWidget<PairingConnectingViewModel> {
  const PairingConnectingViewTablet({super.key});

  @override
  Widget build(context, viewModel) =>
      const Scaffold(body: Center(child: Text('pairing.connecting · tablet')));
}
