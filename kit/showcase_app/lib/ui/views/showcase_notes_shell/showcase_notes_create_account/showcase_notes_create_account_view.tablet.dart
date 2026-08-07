/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for creating a new notes account. The form
/// captures email and password, binds the sign-up op's busy and error streams,
/// and calls the create-account action. Not routed — the signed-out Folders
/// screen embeds it when "Create Account" is tapped, and a back button returns
/// to the sign-in panel.
///
/// Requirements:
/// 1. [Create account] — create-account-with-email-and-otp
/// The form captures email and password, binds the sign-up op's busy/error
/// streams, and calls the create-account action.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │     create account view      │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-2]
///   ┌──────────────────────────────┐
///   │   create account viewmodel   │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. errorMessage$            1. createAccount
///    2. signUpState$
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.tablet.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

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
