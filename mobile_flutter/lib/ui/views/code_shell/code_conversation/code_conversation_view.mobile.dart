// arxa-builder: LIVE — mobile layout of the conversation.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;
import 'package:flutter/material.dart';

import 'code_conversation_body.dart';
import 'code_conversation_viewmodel.dart';

class CodeConversationViewMobile
    extends ViewModelWidget<CodeConversationViewModel> {
  const CodeConversationViewMobile({super.key, required this.viewModel});

  final CodeConversationViewModel viewModel;

  @override
  Widget build(context, _) =>
      CodeConversationBody(key: key, viewModel: viewModel);
}
