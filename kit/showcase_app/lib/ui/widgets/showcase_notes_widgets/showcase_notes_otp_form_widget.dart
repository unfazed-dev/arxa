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
    // Streams-only: the OTP step (email locked / code field / Verify vs Send
    // Code), the inline error, and busy each bind a VM stream — nothing here
    // rebuilds off notifyListeners.
    return KitStreamBuilder<bool>(
      stream: vm.otpRequested$,
      builder: (context, otpRequested) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Standalone capsules (see ShowcaseNotesPasswordFormWidget) — no grouped section chrome.
          ShowcaseNotesAuthTextFieldWidget(
            onChanged: (v) => vm.email = v,
            enabled: !otpRequested,
            placeholder: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          if (otpRequested) ...[
            verticalSpaceSmall,
            ShowcaseNotesAuthTextFieldWidget(
              onChanged: (v) => vm.code = v,
              placeholder: '000000',
              keyboardType: TextInputType.number,
            ),
          ],
          KitStreamBuilder<String?>(
            stream: vm.errorMessage$,
            builder: (context, errorMessage) => errorMessage == null
                ? const SizedBox.shrink()
                : ShowcaseNotesFormErrorRowWidget(message: errorMessage),
          ),
          verticalSpaceMedium,
          KitStreamBuilder<bool>(
            stream: vm.busy$,
            builder: (context, busy) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: kButtonHeightMedium,
                  child: KitNativeButton(
                    label: otpRequested ? 'Verify' : 'Send Code',
                    style: KitButtonStyle.prominentGlass,
                    onPressed: busy
                        ? null
                        : () => otpRequested
                            ? vm.confirmOtp(vm.email, vm.code)
                            : vm.requestOtp(vm.email),
                  ),
                ),
                if (busy) ...[
                  verticalSpaceSmall,
                  const Center(child: KitNativeLoadingIndicator(size: 20)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
