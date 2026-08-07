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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

class ShowcaseNotesCreateAccountViewMobile
    extends ViewModelWidget<ShowcaseNotesCreateAccountViewModel> {
  const ShowcaseNotesCreateAccountViewMobile(
      {required this.onBackToSignIn, super.key});

  final VoidCallback onBackToSignIn;

  @override
  Widget build(
      BuildContext context, ShowcaseNotesCreateAccountViewModel viewModel) {
    final theme = Theme.of(context);

    // Embedded as the signed-out Notes tab body, same as the auth panel — the
    // host provides the Scaffold, so this is a bare scrollable column.
    return SafeArea(
      // bottom: false — host shell uses extendBody, so the form scrolls under
      // the floating tab bar; clearance folded into the scroll padding.
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(abxSize24, abxSize24, abxSize24,
            abxSize24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            appBoxKitVerticalSpaceLarge,
            Column(
              children: [
                Icon(AppBoxKitGlyphs.notes.icon,
                    size: abxSize60, color: theme.colorScheme.primary),
                appBoxKitVerticalSpaceSmall,
                Text(
                  'Create your account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            appBoxKitVerticalSpaceLarge,
            // The form and its reusable field/error pieces come from the
            // central `showcase_notes_widgets` barrel.
            ShowcaseNotesCreateAccountFormWidget(
                viewModel: viewModel, onBackToSignIn: onBackToSignIn),
          ],
        ),
      ),
    );
  }
}
