import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

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

  /// Streams-only house convention: the view never rebuilds off
  /// `notifyListeners` (the viewmodel never calls it) — every live value is
  /// bound with [KitStreamBuilder] at the subtree that needs it.
  @override
  bool get reactive => false;

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
