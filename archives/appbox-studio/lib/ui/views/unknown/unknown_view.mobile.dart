import 'package:appbox_studio/l10n/app_localizations.dart';
import 'package:appbox_studio/ui/common/app_colors.dart';
import 'package:appbox_studio/ui/common/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'unknown_viewmodel.dart';

class UnknownViewMobile extends ViewModelWidget<UnknownViewModel> {
  const UnknownViewMobile({super.key});

  @override
  Widget build(BuildContext context, UnknownViewModel viewModel) {
    return Scaffold(
      backgroundColor: kcBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '404',
              style: TextStyle(
                color: Colors.white,
                fontSize: 80,
                fontWeight: FontWeight.w800,
                height: 0.95,
                letterSpacing: 20.0,
              ),
            ),
            verticalSpaceSmall,
            Text(
              AppLocalizations.of(context).unknownPageNotFound,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 20.0,
                wordSpacing: 10.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
