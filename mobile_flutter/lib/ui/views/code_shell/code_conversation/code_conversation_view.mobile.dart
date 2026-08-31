// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       code_shell_conversation_view
//   comp:          CodeConversationViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'code_conversation_viewmodel.dart';

class CodeConversationViewMobile extends ViewModelWidget<CodeConversationViewModel> {
  const CodeConversationViewMobile({super.key});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('code.conversation · mobile')),
      );
}
