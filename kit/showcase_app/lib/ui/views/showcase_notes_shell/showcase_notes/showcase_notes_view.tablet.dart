import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_viewmodel.dart';

class ShowcaseNotesViewTablet extends ViewModelWidget<ShowcaseNotesViewModel> {
  const ShowcaseNotesViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseNotesView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
