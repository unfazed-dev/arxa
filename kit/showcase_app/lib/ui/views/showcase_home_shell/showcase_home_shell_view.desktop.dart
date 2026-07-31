import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellViewDesktop
    extends ViewModelWidget<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseHomeShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
