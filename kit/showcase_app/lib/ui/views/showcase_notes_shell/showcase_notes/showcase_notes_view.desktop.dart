import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

class ShowcaseNotesViewDesktop extends ViewModelWidget<ShowcaseNotesViewModel> {
  const ShowcaseNotesViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNotesView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
