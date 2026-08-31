// arxa-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.
//   surface:       code_shell_sessions_view
//   comp:          CodeSessionsView
//   id:            code.sessions
//   shell:         code_shell
//   targets:       [ios,android] -> derived form factors [mobile, tablet]
//   deps (builder wires): services/facades/conversation_facade.js
// The widget tree and the form-factor switch are the builder's job (plan 08).
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'code_sessions_viewmodel.dart';

class CodeSessionsView extends StackedView<CodeSessionsViewModel> {
  const CodeSessionsView({super.key});

  @override
  Widget builder(
      BuildContext context, CodeSessionsViewModel viewModel, Widget? child) {
    // ADR-0003: no async without a busy/error surface. Emitted here so the
    // mandate has an emission point rather than only a comment (task #43).
    // No empty state: this skeleton binds no collection, and a generated
    // `isEmpty` over nothing is a check that can only ever pass.
    if (viewModel.isBusy) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (viewModel.hasError) {
      // A sentence, never viewModel.modelError — the raw object leaks
      // internals and reads as a crash. Log it; show this.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Something went wrong loading this screen.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: viewModel.refresh,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(child: Text('code.sessions')),
    );
  }

  @override
  CodeSessionsViewModel viewModelBuilder(context) => CodeSessionsViewModel();
}
