// arxa-scaffolder surface: settings_shell_settings_view (settings.home)
// arxa-builder: unpair (drops NodeId + session token, deregisters push).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitGlyphs, ArxaKitNativeAppBar, ArxaKitNativeLoadingIndicator,
        StackedView;
import 'package:flutter/material.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import 'settings_home_viewmodel.dart';

class SettingsHomeView extends StackedView<SettingsHomeViewModel> {
  const SettingsHomeView({super.key});

  @override
  Widget builder(
      BuildContext context, SettingsHomeViewModel viewModel, Widget? child) {
    final l10n = AppLocalizations.of(context);
    if (viewModel.isBusy) {
      return const Scaffold(
          body: Center(child: ArxaKitNativeLoadingIndicator()));
    }
    return Scaffold(
      appBar: ArxaKitNativeAppBar(title: l10n.settingsTitle),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(ArxaKitGlyphs.signOut.icon),
            title: Text(l10n.settingsUnpair),
            subtitle: Text(l10n.settingsUnpairSubtitle),
            onTap: viewModel.unpair,
          ),
        ],
      ),
    );
  }

  @override
  SettingsHomeViewModel viewModelBuilder(context) => SettingsHomeViewModel();
}
