import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_shell_viewmodel.dart';

class ShowcaseShellViewTablet extends ViewModelWidget<ShowcaseShellViewModel> {
  const ShowcaseShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
