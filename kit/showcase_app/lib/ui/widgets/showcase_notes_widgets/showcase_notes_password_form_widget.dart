import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// Password-mode credential form for the sign-in panel. View-specific composite
/// (wires [ShowcaseNotesAuthViewModel]) — lives in the central
/// `showcase_notes_widgets` home. The reusable pieces ([ShowcaseNotesAuthTextFieldWidget],
/// [ShowcaseNotesFormErrorRowWidget]) come from the same barrel.
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
        // so a AppBoxKitListSection container + divider produces double chrome
        // around the fields. Standalone capsules with plain spacing is the
        // iOS 26 look.
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
        // Streams-only: inline error and busy bind the VM's streams — nothing
        // here rebuilds off notifyListeners.
        AppBoxKitStreamBuilder<String?>(
          stream: vm.errorMessage$,
          builder: (context, errorMessage) => errorMessage == null
              ? const SizedBox.shrink()
              : ShowcaseNotesFormErrorRowWidget(message: errorMessage),
        ),
        appBoxKitVerticalSpaceMedium,
        AppBoxKitStreamBuilder<bool>(
          stream: vm.busy$,
          builder: (context, busy) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: axButtonHeightMedium,
                child: AppBoxKitNativeButton(
                  label: 'Sign In',
                  style: AppBoxKitButtonStyle.prominentGlass,
                  onPressed:
                      busy ? null : () => vm.signInEmail(vm.email, vm.password),
                ),
              ),
              appBoxKitVerticalSpaceSmall,
              SizedBox(
                height: axButtonHeightMedium,
                child: AppBoxKitNativeButton(
                  label: 'Create Account',
                  style: AppBoxKitButtonStyle.plain,
                  // Prefer the owner's panel swap (dedicated create-account view);
                  // inline fake sign-up remains the fallback for bare embeddings.
                  onPressed: busy
                      ? null
                      : onCreateAccount ??
                          () => vm.signUpEmail(vm.email, vm.password),
                ),
              ),
              if (busy) ...[
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
