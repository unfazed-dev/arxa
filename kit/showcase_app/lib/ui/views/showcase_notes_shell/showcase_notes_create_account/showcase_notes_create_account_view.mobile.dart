import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_core/common/kit_app_constants.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:appbox_kit_core/common/kit_ui_helpers.dart';

import 'widgets/widgets.dart';
import 'showcase_notes_create_account_viewmodel.dart';

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
        padding: EdgeInsets.fromLTRB(kSize24, kSize24, kSize24,
            kSize24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            verticalSpaceLarge,
            Column(
              children: [
                Icon(KitGlyphs.notes.icon,
                    size: kSize60, color: theme.colorScheme.primary),
                verticalSpaceSmall,
                Text(
                  'Create your account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            verticalSpaceLarge,
            // The form lives in this view's `widgets/` barrel; its reusable
            // field/error pieces come from the shell's `shared/widgets/` barrel
            // (folder-org gate check C/D).
            CreateAccountForm(
                viewModel: viewModel, onBackToSignIn: onBackToSignIn),
          ],
        ),
      ),
    );
  }
}
