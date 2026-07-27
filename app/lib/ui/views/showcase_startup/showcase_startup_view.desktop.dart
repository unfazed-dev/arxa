import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_startup_viewmodel.dart';

class ShowcaseStartupViewDesktop
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseStartupView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
