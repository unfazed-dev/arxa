// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       studio_shell_studio_session_view
//   comp:          StudioSessionViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'studio_session_viewmodel.dart';

class StudioSessionViewTablet extends ViewModelWidget<StudioSessionViewModel> {
  const StudioSessionViewTablet({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('studio.session · tablet')),
      );
}
