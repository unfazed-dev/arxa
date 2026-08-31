// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       code_shell_sessions_view
//   comp:          CodeSessionsViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'code_sessions_viewmodel.dart';

class CodeSessionsViewTablet extends ViewModelWidget<CodeSessionsViewModel> {
  const CodeSessionsViewTablet({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('code.sessions · tablet')),
      );
}
