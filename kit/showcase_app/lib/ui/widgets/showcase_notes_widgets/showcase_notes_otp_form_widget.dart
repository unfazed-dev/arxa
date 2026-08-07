/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the OTP-mode credential form in the sign-in
/// panel — email, code field (after request), verify/send-code button.
///
/// Requirements:
/// 1. [OTP sign-in] — sign-in-with-email-and-otp
/// The form binds the OTP-requested stream, calls request-OTP, then shows the
/// code field and calls confirm-OTP.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │    notes otp form widget     │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-2]                    [1-3]
///   ┌──────────────────────────────┐
///   │        auth viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. otpRequested$            1. requestOtp
///    2. errorMessage$            2. confirmOtp
///    3. busy$
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_notes_otp_form_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

class ShowcaseNotesOtpFormWidget extends StatelessWidget {
  const ShowcaseNotesOtpFormWidget({super.key, required this.viewModel});

  final ShowcaseNotesAuthViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    // Streams-only: the OTP step (email locked / code field / Verify vs Send
    // Code), the inline error, and busy each bind a VM stream — nothing here
    // rebuilds off notifyListeners.
    return AppBoxKitStreamBuilder<bool>(
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
            appBoxKitVerticalSpaceSmall,
            ShowcaseNotesAuthTextFieldWidget(
              onChanged: (v) => vm.code = v,
              placeholder: '000000',
              keyboardType: TextInputType.number,
            ),
          ],
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
                  height: abxButtonHeightMedium,
                  child: AppBoxKitNativeButton(
                    label: otpRequested ? 'Verify' : 'Send Code',
                    style: AppBoxKitButtonStyle.prominentGlass,
                    onPressed: busy
                        ? null
                        : () => otpRequested
                            ? vm.confirmOtp(vm.email, vm.code)
                            : vm.requestOtp(vm.email),
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
      ),
    );
  }
}
