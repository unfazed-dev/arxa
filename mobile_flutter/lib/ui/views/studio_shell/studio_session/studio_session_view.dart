// arxa-scaffolder surface: studio_shell_studio_session_view (studio.session)
// arxa-builder: the full studio via webview — navigates to the transport's
// loopback studioUrl; whole-screen webview per the screen-level split rule.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitGlyphs, ArxaKitNativeAppBar, ArxaKitNativeIconButton, StackedView;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'studio_session_viewmodel.dart';

class StudioSessionView extends StackedView<StudioSessionViewModel> {
  const StudioSessionView({super.key});

  @override
  Widget builder(
      BuildContext context, StudioSessionViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    final controller = viewModel.controller;
    return Scaffold(
      appBar: ArxaKitNativeAppBar(
        title: l10n.appTitle,
        actions: [
          ArxaKitNativeIconButton(
            glyph: ArxaKitGlyphs.folder,
            onPressed: viewModel.openCodeSessions,
          ),
          ArxaKitNativeIconButton(
            glyph: ArxaKitGlyphs.alerts,
            onPressed: viewModel.openApprovals,
          ),
          ArxaKitNativeIconButton(
            glyph: ArxaKitGlyphs.settings,
            onPressed: viewModel.openSettings,
          ),
        ],
      ),
      body: controller == null
          ? Center(child: Text(l10n.studioNotConnected))
          : WebViewWidget(controller: controller),
    );
  }

  @override
  void onViewModelReady(StudioSessionViewModel viewModel) => viewModel.start();

  @override
  StudioSessionViewModel viewModelBuilder(context) => StudioSessionViewModel();
}
