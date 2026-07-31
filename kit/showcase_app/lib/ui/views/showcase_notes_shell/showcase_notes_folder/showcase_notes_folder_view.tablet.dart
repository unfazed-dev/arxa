import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_folder_viewmodel.dart';

class ShowcaseNotesFolderViewTablet
    extends ViewModelWidget<ShowcaseNotesFolderViewModel> {
  const ShowcaseNotesFolderViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesFolderViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseNotesFolderView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
