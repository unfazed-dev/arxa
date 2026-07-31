import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_shell_viewmodel.dart';

class ShowcaseShellViewDesktop extends ViewModelWidget<ShowcaseShellViewModel> {
  const ShowcaseShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
