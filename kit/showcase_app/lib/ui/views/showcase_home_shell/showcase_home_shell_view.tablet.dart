import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellViewTablet
    extends ViewModelWidget<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseHomeShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
