import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_note_editor_viewmodel.dart';

class ShowcaseNoteEditorViewTablet
    extends ViewModelWidget<ShowcaseNoteEditorViewModel> {
  const ShowcaseNoteEditorViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNoteEditorViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseNoteEditorView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
