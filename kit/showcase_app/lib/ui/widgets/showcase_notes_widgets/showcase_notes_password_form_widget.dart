/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [ArxaKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the password-mode credential form in the
/// sign-in panel — email, password, sign-in button, create-account button.
///
/// Requirements:
/// 1. [Password sign-in] — sign-in-with-email-and-otp
/// The form binds the error and busy streams and calls the sign-in action.
/// 2. [Inline sign-up] — create-account-with-email-and-otp
/// The "Create Account" button calls the sign-up action as a fallback when no
/// owner swap is provided.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │  notes password form widget  │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-2]                    [1-2]
///   ┌──────────────────────────────┐
///   │        auth viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. errorMessage$            1. signInEmail
///    2. busy$                    2. signUpEmail
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_password_form_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

class ShowcaseNotesPasswordFormWidget extends StatelessWidget {
  const ShowcaseNotesPasswordFormWidget({
    super.key,
    required this.viewModel,
    this.onCreateAccount,
  });

  final ShowcaseNotesAuthViewModel viewModel;
  final VoidCallback? onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No grouped section here: CNTextField renders its own native capsule,
        // so a ArxaKitListSection container + divider produces double chrome
        // around the fields. Standalone capsules with plain spacing is the
        // iOS 26 look.
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.email = v,
          placeholder: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        arxaKitVerticalSpaceSmall,
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.password = v,
          placeholder: 'Password',
          obscureText: true,
        ),
        // Streams-only: inline error and busy bind the VM's streams — nothing
        // here rebuilds off notifyListeners.
        ArxaKitStreamBuilder<String?>(
          stream: vm.errorMessage$,
          builder: (context, errorMessage) => errorMessage == null
              ? const SizedBox.shrink()
              : ShowcaseNotesFormErrorRowWidget(message: errorMessage),
        ),
        arxaKitVerticalSpaceMedium,
        ArxaKitStreamBuilder<bool>(
          stream: vm.busy$,
          builder: (context, busy) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: abxButtonHeightMedium,
                child: ArxaKitNativeButton(
                  label: 'Sign In',
                  style: ArxaKitButtonStyle.prominentGlass,
                  onPressed:
                      busy ? null : () => vm.signInEmail(vm.email, vm.password),
                ),
              ),
              arxaKitVerticalSpaceSmall,
              SizedBox(
                height: abxButtonHeightMedium,
                child: ArxaKitNativeButton(
                  label: 'Create Account',
                  style: ArxaKitButtonStyle.plain,
                  // Prefer the owner's panel swap (dedicated create-account view);
                  // inline fake sign-up remains the fallback for bare embeddings.
                  onPressed: busy
                      ? null
                      : onCreateAccount ??
                          () => vm.signUpEmail(vm.email, vm.password),
                ),
              ),
              if (busy) ...[
                arxaKitVerticalSpaceSmall,
                const Center(child: ArxaKitNativeLoadingIndicator(size: 20)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
