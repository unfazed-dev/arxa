import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_notes_create_account_view.desktop.dart';
import 'showcase_notes_create_account_view.tablet.dart';
import 'showcase_notes_create_account_view.mobile.dart';
import 'showcase_notes_create_account_viewmodel.dart';

/// Create-account panel for the Notes seed backend. Not routed: the
/// signed-out [ShowcaseNotesView] embeds it when `showCreateAccount` is set,
/// and [onBackToSignIn] flips back to the sign-in panel — the transient view
/// holds no navigation state (callback props only).
class ShowcaseNotesCreateAccountView
    extends StackedView<ShowcaseNotesCreateAccountViewModel> {
  const ShowcaseNotesCreateAccountView(
      {required this.onBackToSignIn, super.key});

  /// Owner-supplied swap back to the sign-in panel.
  final VoidCallback onBackToSignIn;

  @override
  ShowcaseNotesCreateAccountViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseNotesCreateAccountViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesCreateAccountViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) =>
          ShowcaseNotesCreateAccountViewMobile(onBackToSignIn: onBackToSignIn),
      tablet: (_) =>
          ShowcaseNotesCreateAccountViewTablet(onBackToSignIn: onBackToSignIn),
      desktop: (_) =>
          ShowcaseNotesCreateAccountViewDesktop(onBackToSignIn: onBackToSignIn),
    );
  }
}
