import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

import '../../shared/widgets/widgets.dart';
import '../showcase_notes_auth_viewmodel.dart';

/// OTP-mode credential form for the sign-in panel. View-specific composite
/// (wires [ShowcaseNotesAuthViewModel]); reusable [AuthTextField] +
/// [FormErrorRow] come from the shell's `shared/widgets/` barrel.
class OtpForm extends StatelessWidget {
  const OtpForm({super.key, required this.viewModel});

  final ShowcaseNotesAuthViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Standalone capsules (see PasswordForm) — no grouped section chrome.
        AuthTextField(
          onChanged: (v) => vm.email = v,
          enabled: !vm.otpRequested,
          placeholder: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        if (vm.otpRequested) ...[
          verticalSpaceSmall,
          AuthTextField(
            onChanged: (v) => vm.code = v,
            placeholder: '000000',
            keyboardType: TextInputType.number,
          ),
        ],
        if (vm.errorMessage != null) FormErrorRow(message: vm.errorMessage!),
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
