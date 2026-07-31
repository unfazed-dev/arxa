import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_create_account_view.mobile.dart';
import 'showcase_notes_create_account_viewmodel.dart';

/// Desktop mirrors tablet: centered mobile column at form width.
class ShowcaseNotesCreateAccountViewDesktop
    extends ViewModelWidget<ShowcaseNotesCreateAccountViewModel> {
  const ShowcaseNotesCreateAccountViewDesktop(
      {required this.onBackToSignIn, super.key});

  final VoidCallback onBackToSignIn;

  @override
  Widget build(
      BuildContext context, ShowcaseNotesCreateAccountViewModel viewModel) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ShowcaseNotesCreateAccountViewMobile(
            onBackToSignIn: onBackToSignIn),
      ),
    );
  }
}
