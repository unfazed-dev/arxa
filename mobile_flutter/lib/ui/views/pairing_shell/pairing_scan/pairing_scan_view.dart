// arxa-scaffolder surface: pairing_shell_pairing_scan_view (pairing.scan)
// arxa-builder: camera QR scan (mobile_scanner) + manual ticket entry.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeAppBar, ArxaKitNativeLoadingIndicator,
        ArxaKitNativeTextField, StackedView;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'pairing_scan_viewmodel.dart';

class PairingScanView extends StackedView<PairingScanViewModel> {
  const PairingScanView({super.key});

  @override
  Widget builder(
      BuildContext context, PairingScanViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    if (viewModel.isBusy) {
      return const Scaffold(
          body: Center(child: ArxaKitNativeLoadingIndicator()));
    }
    return Scaffold(
      appBar: ArxaKitNativeAppBar(title: l10n.pairingScanTitle),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final value = capture.barcodes.isEmpty
                    ? null
                    : capture.barcodes.first.rawValue;
                if (value != null) viewModel.submitTicket(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ArxaKitNativeTextField(
              placeholder: l10n.pairingManualHint,
              onSubmitted: viewModel.submitTicket,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void onViewModelReady(PairingScanViewModel viewModel) => viewModel.start();

  @override
  PairingScanViewModel viewModelBuilder(context) => PairingScanViewModel();
}
