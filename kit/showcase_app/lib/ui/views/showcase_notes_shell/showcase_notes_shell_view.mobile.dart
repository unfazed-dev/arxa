import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellViewMobile
    extends ViewModelWidget<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesShellViewModel viewModel) {
    return const NestedRouter();
  }
}
