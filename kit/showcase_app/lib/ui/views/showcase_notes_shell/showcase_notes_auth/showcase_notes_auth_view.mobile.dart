/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [ArxaKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for signing in to the notes app. A segmented
/// control picks password or OTP mode; below it sit the social sign-in buttons
/// (Google, Apple, Guest). The screen is not routed — the signed-out Folders
/// screen embeds it as the Notes tab root, and the session stream swaps it for
/// the Folders list in place when a session appears.
///
/// Requirements:
/// 1. [Email sign-in] — sign-in-with-email-and-otp
/// The segmented control picks password or OTP mode; the form binds the mode
/// stream and calls the sign-in, request-OTP, and confirm-OTP actions.
/// 2. [Google sign-in] — sign-in-with-google
/// The "Continue with Google" button calls the Google action.
/// 3. [Apple sign-in] — sign-in-with-apple
/// The "Continue with Apple" button calls the Apple action.
/// 4. [Anonymous sign-in] — continue-anonymously
/// The "Continue as Guest" button calls the anonymous action.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │          auth view           │
///   └──────────────────────────────┘
///   ACT ▼                    ▲ STRM
///   [1-7]                    [1-4]
///   ┌──────────────────────────────┐
///   │        auth viewmodel        │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  streams (STRM)              actions (ACT)
///    1. mode$                    1. setMode
///    2. otpRequested$            2. signInEmail
///    3. errorMessage$            3. requestOtp
///    4. busy$                    4. confirmOtp
///                                5. google
///                                6. apple
///                                7. anonymous
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';

class ShowcaseNotesAuthViewMobile
    extends ViewModelWidget<ShowcaseNotesAuthViewModel> {
  const ShowcaseNotesAuthViewMobile({this.onCreateAccount, super.key});

  /// When set, "Create Account" swaps to the dedicated panel (owner-managed)
  /// instead of the inline fake sign-up.
  final VoidCallback? onCreateAccount;

  @override
  Widget build(BuildContext context, ShowcaseNotesAuthViewModel viewModel) {
    final theme = Theme.of(context);

    // The signed-out Notes tab embeds this view as its body
    // (showcase_notes_view.mobile.dart), so it already has a Scaffold — no
    // nested Scaffold here, and no nav bar: auth is a root surface with no
    // back context. The brand hero carries the visual anchor instead.
    return SafeArea(
      // bottom: false — host shell uses extendBody, so the form scrolls under
      // the floating tab bar; clearance folded into the scroll padding.
      bottom: false,
      // Auth is a single focused column, not a list, so the scope's stagger
      // steps across four blocks (hero → form → social → hint) rather than
      // per-row. ArxaKitWake is one-shot per scope, so the credential block's
      // mode-toggle rebuild does NOT replay its entrance (no keys needed —
      // flutter_animate required ValueKeys for the same guarantee).
      child: ArxaKitMotionScope(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              abxSize24,
              abxSize24,
              abxSize24,
              abxSize24 +
                  MediaQuery.paddingOf(context).bottom +
                  kShowcaseTabBarBlockHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              arxaKitVerticalSpaceLarge,
              // (0) Brand mark + wordmark — the single signature hero. No
              // subtitle: the wordmark + the form is enough, a marketing tagline
              // here would be slop.
              Column(
                children: [
                  Icon(ArxaKitGlyphs.notes.icon,
                      size: abxSize60, color: theme.colorScheme.primary),
                  arxaKitVerticalSpaceSmall,
                  Text(
                    'Arxa Notes',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ).wake(order: 0),
              arxaKitVerticalSpaceLarge,

              // (1) Credential block: mode toggle + the form the mode selects.
              // The mode binds via ArxaKitStreamBuilder (streams-only — the VM
              // never calls notifyListeners). The form widgets and their
              // reusable field/error pieces come from the central
              // `showcase_notes_widgets` barrel.
              ArxaKitStreamBuilder<ShowcaseNotesAuthMode>(
                stream: viewModel.mode$,
                builder: (context, mode) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArxaKitNativeSegmentedControl(
                      segments: [
                        for (final m in ShowcaseNotesAuthMode.values) m.label
                      ],
                      selectedIndex: mode.index,
                      onChanged: (i) =>
                          viewModel.setMode(ShowcaseNotesAuthMode.values[i]),
                    ),
                    arxaKitVerticalSpaceMedium,
                    if (mode == ShowcaseNotesAuthMode.password)
                      ShowcaseNotesPasswordFormWidget(
                          viewModel: viewModel,
                          onCreateAccount: onCreateAccount)
                    else
                      ShowcaseNotesOtpFormWidget(viewModel: viewModel),
                  ],
                ),
              ).wake(order: 1),

              // (2) Alternatives — demoted below an "or" divider. Stacked full
              // width (not a cramped 3-across row) so each provider reads as a
              // peer secondary action, clearly below the prominent primary CTA.
              // Busy binds via ArxaKitStreamBuilder on the VM's busy$ (composed
              // from the per-op ArxaKitAction.state$ streams) — while any auth op
              // runs, every button disables, same as the old global setBusy.
              ArxaKitStreamBuilder<bool>(
                stream: viewModel.busy$,
                builder: (context, busy) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    arxaKitVerticalSpaceLarge,
                    Row(
                      children: [
                        Expanded(child: Divider(color: theme.dividerColor)),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: abxSize12),
                          child: Text('or',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(child: Divider(color: theme.dividerColor)),
                      ],
                    ),
                    arxaKitVerticalSpaceMedium,
                    SizedBox(
                      height: abxButtonHeightMedium,
                      child: ArxaKitNativeButton(
                        label: 'Continue with Google',
                        // glass (default) renders real Liquid Glass on iOS 26 and
                        // ButtonM3E on Android — the native peer to the primary CTA.
                        style: ArxaKitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.google,
                      ),
                    ),
                    arxaKitVerticalSpaceSmall,
                    SizedBox(
                      height: abxButtonHeightMedium,
                      child: ArxaKitNativeButton(
                        label: 'Continue with Apple',
                        style: ArxaKitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.apple,
                      ),
                    ),
                    arxaKitVerticalSpaceSmall,
                    SizedBox(
                      height: abxButtonHeightMedium,
                      child: ArxaKitNativeButton(
                        label: 'Continue as Guest',
                        style: ArxaKitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.anonymous,
                      ),
                    ),
                  ],
                ),
              ).wake(order: 2),

              // (3) Seed hint — stays in glass at the tail; it's reference copy,
              // not action, so it earns the card chrome.
              arxaKitVerticalSpaceLarge,
              ArxaKitGlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(ArxaKitGlyphs.info.icon,
                        size: abxSize18,
                        color: theme.colorScheme.onSurfaceVariant),
                    arxaKitHorizontalSpaceSmall,
                    Expanded(
                      child: Text(
                        'Seed backend: any password works. Try evan@seed.local '
                        '(seeded notes) or guest@seed.local. OTP code: any, '
                        'e.g. 000000.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ).wake(order: 3),
            ],
          ),
        ),
      ),
    );
  }
}
