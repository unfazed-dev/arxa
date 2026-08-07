/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for signing in to the notes app. A segmented
/// control picks password or OTP mode; below it sit the social sign-in buttons
/// (Google, Apple, Guest). The screen is not routed — the signed-out Folders
/// screen embeds it as the Notes tab root, and the session stream swaps it for
/// the Folders list in place when a session appears.
///
/// Requirements:
/// 1. [Email sign-in] — sign-in-with-email-and-otp
/// The segmented control picks password or OTP mode; the form binds the mode
/// stream and calls the sign-in, request-OTP, and confirm-OTP actions.
/// 2. [Google sign-in] — sign-in-with-google
/// The "Continue with Google" button calls the Google action.
/// 3. [Apple sign-in] — sign-in-with-apple
/// The "Continue with Apple" button calls the Apple action.
/// 4. [Anonymous sign-in] — continue-anonymously
/// The "Continue as Guest" button calls the anonymous action.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │          auth view           │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-7]                    [1-4]
///   ┌──────────────────────────────┐
///   │        auth viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. mode$                    1. setMode
///    2. otpRequested$            2. signInEmail
///    3. errorMessage$            3. requestOtp
///    4. busy$                    4. confirmOtp
///                                5. google
///                                6. apple
///                                7. anonymous
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';

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
