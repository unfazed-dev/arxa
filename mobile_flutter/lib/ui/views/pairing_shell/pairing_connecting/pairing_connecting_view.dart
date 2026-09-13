// arxa-scaffolder surface: pairing_shell_connecting_view (pairing.connecting)
// arxa-builder: connection-state surface; states mirror ConnectionStatus.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show
        ArxaKitNativeButton,
        ArxaKitNativeLoadingIndicator,
        StackedView,
        arxaKitVerticalSpaceSmall;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

import 'pairing_connecting_viewmodel.dart';

class PairingConnectingView extends StackedView<PairingConnectingViewModel> {
  const PairingConnectingView({super.key});

  @override
  Widget builder(
    BuildContext context,
    PairingConnectingViewModel viewModel,
    Widget? child,
  ) {
    final l10n = AppLocalizations.of(context);
    final error = viewModel.connectionError;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error == null) ...[
              const ArxaKitNativeLoadingIndicator(),
              arxaKitVerticalSpaceSmall,
              Text(switch (viewModel.state) {
                ArxaConnectionState.pairing => l10n.connectingPairing,
                ArxaConnectionState.connecting => l10n.connectingConnecting,
                ArxaConnectionState.connected => l10n.connectingConnected,
                _ => l10n.connectingWaiting,
              }),
            ] else ...[
              Text(l10n.connectingFailed),
              arxaKitVerticalSpaceSmall,
              ArxaKitNativeButton(
                onPressed: viewModel.refresh,
                label: l10n.tryAgain,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void onViewModelReady(PairingConnectingViewModel viewModel) =>
      viewModel.start();

  @override
  PairingConnectingViewModel viewModelBuilder(context) =>
      PairingConnectingViewModel();
}
