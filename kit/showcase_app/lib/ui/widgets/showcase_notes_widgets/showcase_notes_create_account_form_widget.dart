/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the create-account form in the dedicated
/// sign-up panel — email, password, create-account button, back-to-sign-in
/// button.
///
/// Requirements:
/// 1. [Create account] — create-account-with-email-and-otp
/// The form binds the sign-up op's busy/error streams and calls the
/// create-account action.
///
/// Relationships:
///
///   ┌──────────────────────────────────┐
///   │ notes create account form widget │
///   └──────────────────────────────────┘
///   ACT ▼                        ▲ STRM
///   [1-2]
///   ┌──────────────────────────────────┐
///   │     create account viewmodel     │
///   └──────────────────────────────────┘
///        ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. errorMessage$            1. createAccount
///    2. signUpState$
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_create_account_form_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// Create-account form for the dedicated sign-up panel. View-specific composite
/// (wires [ShowcaseNotesCreateAccountViewModel]); reusable [ShowcaseNotesAuthTextFieldWidget] +
/// [ShowcaseNotesFormErrorRowWidget] come from the central `showcase_notes_widgets` barrel.
class ShowcaseNotesCreateAccountFormWidget extends StatelessWidget {
  const ShowcaseNotesCreateAccountFormWidget({
    super.key,
    required this.viewModel,
    required this.onBackToSignIn,
  });

  final ShowcaseNotesCreateAccountViewModel viewModel;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.email = v,
          placeholder: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        appBoxKitVerticalSpaceSmall,
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.password = v,
          placeholder: 'Password',
          obscureText: true,
        ),
        // Streams-only: inline error binds the VM's errorMessage$; busy binds
        // the sign-up op's AppBoxKitAction.state$ — no notifyListeners anywhere.
        AppBoxKitStreamBuilder<String?>(
          stream: vm.errorMessage$,
          builder: (context, errorMessage) => errorMessage == null
              ? const SizedBox.shrink()
              : ShowcaseNotesFormErrorRowWidget(message: errorMessage),
        ),
        appBoxKitVerticalSpaceMedium,
        AppBoxKitStreamBuilder<AppBoxKitActionState>(
          stream: vm.signUpState$,
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: abxButtonHeightMedium,
                child: AppBoxKitNativeButton(
                  label: 'Create Account',
                  style: AppBoxKitButtonStyle.prominentGlass,
                  onPressed: state.busy
                      ? null
                      : () => vm.createAccount(vm.email, vm.password),
                ),
              ),
              appBoxKitVerticalSpaceSmall,
              SizedBox(
                height: abxButtonHeightMedium,
                child: AppBoxKitNativeButton(
                  label: 'Back to Sign In',
                  style: AppBoxKitButtonStyle.plain,
                  onPressed: state.busy ? null : onBackToSignIn,
                ),
              ),
              if (state.busy) ...[
                appBoxKitVerticalSpaceSmall,
                const Center(child: AppBoxKitNativeLoadingIndicator(size: 20)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
