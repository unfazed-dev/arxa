// arxa-scaffolder surface: pairing_shell_push_permission_view
// arxa-builder: OS push-permission prompt; skippable (approvals stay in-app).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show
        ArxaKitNativeButton,
        ArxaKitNativeLoadingIndicator,
        StackedView,
        arxaKitVerticalSpaceMedium,
        arxaKitVerticalSpaceXSmall;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'pairing_push_permission_viewmodel.dart';

class PairingPushPermissionView
    extends StackedView<PairingPushPermissionViewModel> {
  const PairingPushPermissionView({super.key});

  @override
  Widget builder(
    BuildContext context,
    PairingPushPermissionViewModel viewModel,
    Widget? child,
  ) {
    final l10n = AppLocalizations.of(context);
    if (viewModel.isBusy) {
      return const Scaffold(
        body: Center(child: ArxaKitNativeLoadingIndicator()),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.pushTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              arxaKitVerticalSpaceXSmall,
              Text(l10n.pushBody, textAlign: TextAlign.center),
              arxaKitVerticalSpaceMedium,
              ArxaKitNativeButton(
                onPressed: viewModel.allow,
                label: l10n.pushAllow,
              ),
              arxaKitVerticalSpaceXSmall,
              ArxaKitNativeButton(
                onPressed: viewModel.skip,
                label: l10n.pushSkip,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  PairingPushPermissionViewModel viewModelBuilder(context) =>
      PairingPushPermissionViewModel();
}
