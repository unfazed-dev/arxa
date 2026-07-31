import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_auth_viewmodel.dart';

class ShowcaseNotesAuthViewDesktop
    extends ViewModelWidget<ShowcaseNotesAuthViewModel> {
  const ShowcaseNotesAuthViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesAuthViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseNotesAuthView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
