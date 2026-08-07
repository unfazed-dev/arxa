import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_viewmodel.dart';

class ShowcaseApplicationShellViewDesktop extends ViewModelWidget<ShowcaseApplicationShellViewModel> {
  const ShowcaseApplicationShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseApplicationShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseApplicationShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
