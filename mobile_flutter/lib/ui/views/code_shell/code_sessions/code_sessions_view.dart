// arxa-builder: LIVE — the code sessions list, composing the form-factor
// siblings (mobile / tablet) over the shared body.
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show
        ArxaKitGlyphs,
        ArxaKitNativeAppBar,
        ArxaKitNativeIconButton,
        StackedView;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'code_sessions_view.mobile.dart';
import 'code_sessions_view.tablet.dart';
import 'code_sessions_viewmodel.dart';

class CodeSessionsView extends StackedView<CodeSessionsViewModel> {
  const CodeSessionsView({super.key});

  @override
  Widget builder(
    BuildContext context,
    CodeSessionsViewModel viewModel,
    Widget? child,
  ) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ArxaKitNativeAppBar(
        title: l10n.codeSessionsTitle,
        actions: [
          Tooltip(
            message: l10n.tryAgain,
            child: ArxaKitNativeIconButton(
              glyph: ArxaKitGlyphs.refresh,
              onPressed: viewModel.refresh,
            ),
          ),
          // The studio session is the paired home; this is the way back.
          Tooltip(
            message: l10n.approvalsOpenStudio,
            child: ArxaKitNativeIconButton(
              glyph: ArxaKitGlyphs.home,
              onPressed: viewModel.goToStudio,
            ),
          ),
        ],
      ),
      body: MediaQuery.sizeOf(context).width >= 600
          ? CodeSessionsViewTablet(
              key: const ValueKey('tablet'),
              viewModel: viewModel,
            )
          : CodeSessionsViewMobile(
              key: const ValueKey('mobile'),
              viewModel: viewModel,
            ),
    );
  }

  @override
  void onViewModelReady(CodeSessionsViewModel viewModel) {
    viewModel
      ..listenTransport()
      ..listenLive()
      ..refresh();
  }

  @override
  CodeSessionsViewModel viewModelBuilder(context) => CodeSessionsViewModel();
}
