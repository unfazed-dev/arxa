import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

/// OTP-mode credential form for the sign-in panel. View-specific composite
/// (wires [ShowcaseNotesAuthViewModel]); reusable [ShowcaseNotesAuthTextFieldWidget] +
/// [ShowcaseNotesFormErrorRowWidget] come from the central `showcase_notes_widgets` barrel.
class ShowcaseNotesOtpFormWidget extends StatelessWidget {
  const ShowcaseNotesOtpFormWidget({super.key, required this.viewModel});

  final ShowcaseNotesAuthViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Standalone capsules (see ShowcaseNotesPasswordFormWidget) — no grouped section chrome.
        ShowcaseNotesAuthTextFieldWidget(
          onChanged: (v) => vm.email = v,
          enabled: !vm.otpRequested,
          placeholder: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        if (vm.otpRequested) ...[
          verticalSpaceSmall,
          ShowcaseNotesAuthTextFieldWidget(
            onChanged: (v) => vm.code = v,
            placeholder: '000000',
            keyboardType: TextInputType.number,
          ),
        ],
        if (vm.errorMessage != null) ShowcaseNotesFormErrorRowWidget(message: vm.errorMessage!),
        verticalSpaceMedium,
        SizedBox(
          height: kButtonHeightMedium,
          child: KitNativeButton(
            label: vm.otpRequested ? 'Verify' : 'Send Code',
            style: KitButtonStyle.prominentGlass,
            onPressed: vm.isBusy
                ? null
                : () => vm.otpRequested
                    ? vm.confirmOtp(vm.email, vm.code)
                    : vm.requestOtp(vm.email),
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
