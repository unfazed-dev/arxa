import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';

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
      // per-row. KitWake is one-shot per scope, so the credential block's
      // mode-toggle rebuild does NOT replay its entrance (no keys needed —
      // flutter_animate required ValueKeys for the same guarantee).
      child: KitMotionScope(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              kSize24,
              kSize24,
              kSize24,
              kSize24 +
                  MediaQuery.paddingOf(context).bottom +
                  kShowcaseTabBarBlockHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              verticalSpaceLarge,
              // (0) Brand mark + wordmark — the single signature hero. No
              // subtitle: the wordmark + the form is enough, a marketing tagline
              // here would be slop.
              Column(
                children: [
                  Icon(KitGlyphs.notes.icon,
                      size: kSize60, color: theme.colorScheme.primary),
                  verticalSpaceSmall,
                  Text(
                    'Kit Notes',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ).wake(order: 0),
              verticalSpaceLarge,

              // (1) Credential block: mode toggle + the form the mode selects.
              // The mode binds via KitStreamBuilder (streams-only — the VM
              // never calls notifyListeners). The form widgets and their
              // reusable field/error pieces come from the central
              // `showcase_notes_widgets` barrel.
              KitStreamBuilder<NotesAuthMode>(
                stream: viewModel.mode$,
                builder: (context, mode) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KitNativeSegmentedControl(
                      segments: const ['Password', 'OTP'],
                      selectedIndex: NotesAuthMode.values.indexOf(mode),
                      onChanged: (i) =>
                          viewModel.setMode(NotesAuthMode.values[i]),
                    ),
                    verticalSpaceMedium,
                    if (mode == NotesAuthMode.password)
                      ShowcaseNotesPasswordFormWidget(
                          viewModel: viewModel, onCreateAccount: onCreateAccount)
                    else
                      ShowcaseNotesOtpFormWidget(viewModel: viewModel),
                  ],
                ),
              ).wake(order: 1),

              // (2) Alternatives — demoted below an "or" divider. Stacked full
              // width (not a cramped 3-across row) so each provider reads as a
              // peer secondary action, clearly below the prominent primary CTA.
              // Busy binds via KitStreamBuilder on the VM's busy$ (composed
              // from the per-op KitAction.state$ streams) — while any auth op
              // runs, every button disables, same as the old global setBusy.
              KitStreamBuilder<bool>(
                stream: viewModel.busy$,
                builder: (context, busy) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    verticalSpaceLarge,
                    Row(
                      children: [
                        Expanded(child: Divider(color: theme.dividerColor)),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: kSize12),
                          child: Text('or',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(child: Divider(color: theme.dividerColor)),
                      ],
                    ),
                    verticalSpaceMedium,
                    SizedBox(
                      height: kButtonHeightMedium,
                      child: KitNativeButton(
                        label: 'Continue with Google',
                        // glass (default) renders real Liquid Glass on iOS 26 and
                        // ButtonM3E on Android — the native peer to the primary CTA.
                        style: KitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.google,
                      ),
                    ),
                    verticalSpaceSmall,
                    SizedBox(
                      height: kButtonHeightMedium,
                      child: KitNativeButton(
                        label: 'Continue with Apple',
                        style: KitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.apple,
                      ),
                    ),
                    verticalSpaceSmall,
                    SizedBox(
                      height: kButtonHeightMedium,
                      child: KitNativeButton(
                        label: 'Continue as Guest',
                        style: KitButtonStyle.glass,
                        onPressed: busy ? null : viewModel.anonymous,
                      ),
                    ),
                  ],
                ),
              ).wake(order: 2),

              // (3) Seed hint — stays in glass at the tail; it's reference copy,
              // not action, so it earns the card chrome.
              verticalSpaceLarge,
              KitGlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(KitGlyphs.info.icon,
                        size: kSize18,
                        color: theme.colorScheme.onSurfaceVariant),
                    horizontalSpaceSmall,
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
