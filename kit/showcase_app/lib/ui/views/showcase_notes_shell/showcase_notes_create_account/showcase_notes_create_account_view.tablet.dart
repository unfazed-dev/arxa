import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

/// Tablet mirrors the auth panel's convention: the notes shell is a
/// mobile-first showcase, so larger form factors reuse the mobile column
/// (which is width-constrained by its host) rather than a bespoke layout.
class ShowcaseNotesCreateAccountViewTablet
    extends ViewModelWidget<ShowcaseNotesCreateAccountViewModel> {
  const ShowcaseNotesCreateAccountViewTablet(
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
