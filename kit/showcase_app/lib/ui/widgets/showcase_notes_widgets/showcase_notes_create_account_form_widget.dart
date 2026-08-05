import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

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
        verticalSpaceSmall,
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.password = v,
          placeholder: 'Password',
          obscureText: true,
        ),
        if (vm.errorMessage != null) ShowcaseNotesFormErrorRowWidget(message: vm.errorMessage!),
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
