// arxa-builder: LIVE — one session's conversation, composing the
// form-factor siblings (mobile / tablet) over the shared body. The
// sessionId route arg picks the transcript.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeAppBar, StackedView;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'code_conversation_view.mobile.dart';
import 'code_conversation_view.tablet.dart';
import 'code_conversation_viewmodel.dart';

class CodeConversationView extends StackedView<CodeConversationViewModel> {
  const CodeConversationView({required this.sessionId, super.key});

  /// The dsh session whose transcript this view shows (route arg).
  final String sessionId;

  @override
  Widget builder(
      BuildContext context, CodeConversationViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ArxaKitNativeAppBar(title: l10n.codeConversationTitle),
      body: MediaQuery.sizeOf(context).width >= 600
          ? CodeConversationViewTablet(
              key: const ValueKey('tablet'), viewModel: viewModel)
          : CodeConversationViewMobile(
              key: const ValueKey('mobile'), viewModel: viewModel),
    );
  }

  @override
  void onViewModelReady(CodeConversationViewModel viewModel) {
    viewModel
      ..listenTransport()
      ..listenLive()
      ..refresh();
  }

  @override
  CodeConversationViewModel viewModelBuilder(context) =>
      CodeConversationViewModel(sessionId);
}
