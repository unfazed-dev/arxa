import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellViewDesktop
    extends ViewModelWidget<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNotesShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
