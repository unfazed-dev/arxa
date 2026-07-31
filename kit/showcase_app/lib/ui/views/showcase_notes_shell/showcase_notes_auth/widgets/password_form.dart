import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

import '../../shared/widgets/widgets.dart';
import '../showcase_notes_auth_viewmodel.dart';

/// Password-mode credential form for the sign-in panel. View-specific composite
/// (wires [ShowcaseNotesAuthViewModel]) — lives in the view's own `widgets/`
/// per the folder-org gate (check D). The reusable pieces ([AuthTextField],
/// [FormErrorRow]) come from the shell's `shared/widgets/` barrel.
class PasswordForm extends StatelessWidget {
  const PasswordForm({
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
        // so a KitListSection container + divider produces double chrome
        // around the fields. Standalone capsules with plain spacing is the
        // iOS 26 look.
        AuthTextField(
          onChanged: (v) => vm.email = v,
          placeholder: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        verticalSpaceSmall,
        AuthTextField(
          onChanged: (v) => vm.password = v,
          placeholder: 'Password',
          obscureText: true,
        ),
        if (vm.errorMessage != null) FormErrorRow(message: vm.errorMessage!),
        verticalSpaceMedium,
        SizedBox(
          height: kButtonHeightMedium,
          child: KitNativeButton(
            label: 'Sign In',
            style: KitButtonStyle.prominentGlass,
            onPressed:
                vm.isBusy ? null : () => vm.signInEmail(vm.email, vm.password),
          ),
        ),
        verticalSpaceSmall,
        SizedBox(
          height: kButtonHeightMedium,
          child: KitNativeButton(
            label: 'Create Account',
            style: KitButtonStyle.plain,
            // Prefer the owner's panel swap (dedicated create-account view);
            // inline fake sign-up remains the fallback for bare embeddings.
            onPressed: vm.isBusy
                ? null
                : onCreateAccount ??
                    () => vm.signUpEmail(vm.email, vm.password),
          ),
        ),
        if (vm.isBusy) ...[
          verticalSpaceSmall,
          const Center(child: KitNativeLoadingIndicator(size: 20)),
        ],
      ],
    );
  }
}
