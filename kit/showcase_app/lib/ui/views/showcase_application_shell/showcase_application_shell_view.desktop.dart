/// The application shell's form-factor variant. A view is actions in, streams
/// out.
///
/// This is the user interface for the showcase's tabbed root shell — the
/// variant renders the tab host (mobile) or a placeholder (desktop, tablet).
///
/// Requirements:
/// 1. [Tab host] — shell-demos.home-and-application-shells.browse-the-application-shell
/// The variant renders the application tab shell.
///
/// Relationships:
///
///        ┌───────────────────────────┐
///        │ application shell variant │
///        └───────────────────────────┘
///       ┌─────────────────────────────┐
///       │ application shell viewmodel │
///       └─────────────────────────────┘
///         ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_application_shell/showcase_application_shell_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_viewmodel.dart';

class ShowcaseApplicationShellViewDesktop extends ViewModelWidget<ShowcaseApplicationShellViewModel> {
  const ShowcaseApplicationShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseApplicationShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseApplicationShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
