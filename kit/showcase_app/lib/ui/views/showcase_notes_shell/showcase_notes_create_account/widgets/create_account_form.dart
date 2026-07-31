import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

import '../../shared/widgets/widgets.dart';
import '../showcase_notes_create_account_viewmodel.dart';

/// Create-account form for the dedicated sign-up panel. View-specific composite
/// (wires [ShowcaseNotesCreateAccountViewModel]); reusable [AuthTextField] +
/// [FormErrorRow] come from the shell's `shared/widgets/` barrel.
class CreateAccountForm extends StatelessWidget {
  const CreateAccountForm({
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
            label: 'Create Account',
            style: KitButtonStyle.prominentGlass,
            onPressed: vm.isBusy
                ? null
                : () => vm.createAccount(vm.email, vm.password),
          ),
        ),
        verticalSpaceSmall,
        SizedBox(
          height: kButtonHeightMedium,
          child: KitNativeButton(
            label: 'Back to Sign In',
            style: KitButtonStyle.plain,
            onPressed: vm.isBusy ? null : onBackToSignIn,
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
