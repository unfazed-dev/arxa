import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellViewDesktop
    extends ViewModelWidget<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseProfileShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
