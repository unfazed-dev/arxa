// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       code_shell_sessions_view
//   comp:          CodeSessionsViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'code_sessions_viewmodel.dart';

class CodeSessionsViewMobile extends ViewModelWidget<CodeSessionsViewModel> {
  const CodeSessionsViewMobile({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('code.sessions · mobile')),
      );
}
