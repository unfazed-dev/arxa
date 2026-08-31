// arxa-scaffolder: tablet layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       code_shell_conversation_view
//   comp:          CodeConversationViewTablet
//   factor:        tablet   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'code_conversation_viewmodel.dart';

class CodeConversationViewTablet extends ViewModelWidget<CodeConversationViewModel> {
  const CodeConversationViewTablet({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('code.conversation · tablet')),
      );
}
