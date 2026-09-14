// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       pairing_shell_pairing_scan_view
//   comp:          PairingScanViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'pairing_scan_viewmodel.dart';

class PairingScanViewTablet extends ViewModelWidget<PairingScanViewModel> {
  const PairingScanViewTablet({super.key});

  @override
  Widget build(context, viewModel) =>
      const Scaffold(body: Center(child: Text('pairing.scan · tablet')));
}
