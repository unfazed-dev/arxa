import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellViewTablet
    extends ViewModelWidget<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseNotesShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
