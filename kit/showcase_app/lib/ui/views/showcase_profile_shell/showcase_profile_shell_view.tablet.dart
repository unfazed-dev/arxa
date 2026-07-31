import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellViewTablet
    extends ViewModelWidget<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseProfileShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
