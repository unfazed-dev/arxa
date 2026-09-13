// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       pairing_shell_pairing_scan_view
//   comp:          PairingScanViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'pairing_scan_viewmodel.dart';

class PairingScanViewMobile extends ViewModelWidget<PairingScanViewModel> {
  const PairingScanViewMobile({super.key});

  @override
  Widget build(context, viewModel) =>
      const Scaffold(body: Center(child: Text('pairing.scan · mobile')));
}
