// arxa-scaffolder: mobile layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       settings_shell_settings_view
//   comp:          SettingsHomeViewMobile
//   factor:        mobile   (derived from targets=[ios,android])
import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelWidget;

import 'settings_home_viewmodel.dart';

class SettingsHomeViewMobile extends ViewModelWidget<SettingsHomeViewModel> {
  const SettingsHomeViewMobile({super.key});

  @override
  Widget build(context, viewModel) =>
      const Scaffold(body: Center(child: Text('settings.home · mobile')));
}
