import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/common/appbox_kit_ui_helpers.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

class ShowcaseNotesCreateAccountViewMobile
    extends ViewModelWidget<ShowcaseNotesCreateAccountViewModel> {
  const ShowcaseNotesCreateAccountViewMobile(
      {required this.onBackToSignIn, super.key});

  final VoidCallback onBackToSignIn;

  @override
  Widget build(
      BuildContext context, ShowcaseNotesCreateAccountViewModel viewModel) {
    final theme = Theme.of(context);

    // Embedded as the signed-out Notes tab body, same as the auth panel — the
    // host provides the Scaffold, so this is a bare scrollable column.
    return SafeArea(
      // bottom: false — host shell uses extendBody, so the form scrolls under
      // the floating tab bar; clearance folded into the scroll padding.
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(axSize24, axSize24, axSize24,
            axSize24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            appBoxKitVerticalSpaceLarge,
            Column(
              children: [
                Icon(AppBoxKitGlyphs.notes.icon,
                    size: axSize60, color: theme.colorScheme.primary),
                appBoxKitVerticalSpaceSmall,
                Text(
                  'Create your account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            appBoxKitVerticalSpaceLarge,
            // The form and its reusable field/error pieces come from the
            // central `showcase_notes_widgets` barrel.
            ShowcaseNotesCreateAccountFormWidget(
                viewModel: viewModel, onBackToSignIn: onBackToSignIn),
          ],
        ),
      ),
    );
  }
}
