import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';

/// Fake-auth smoke surface for the Notes seed backend. Not routed: the
/// signed-out [ShowcaseNotesView] renders it as the Notes tab root, and the session
/// stream swaps it for the Folders list in place — no route push, no jump.
class ShowcaseNotesAuthView extends StackedView<ShowcaseNotesAuthViewModel> {
  const ShowcaseNotesAuthView({this.onCreateAccount, super.key});

  /// When provided, the password form's "Create Account" button hands off to
  /// the owner (which swaps in the dedicated create-account panel) instead of
  /// signing up inline.
  final VoidCallback? onCreateAccount;

  @override
  ShowcaseNotesAuthViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseNotesAuthViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesAuthViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) =>
          ShowcaseNotesAuthViewMobile(onCreateAccount: onCreateAccount),
      tablet: (_) => const ShowcaseNotesAuthViewTablet(),
      desktop: (_) => const ShowcaseNotesAuthViewDesktop(),
    );
  }
}
