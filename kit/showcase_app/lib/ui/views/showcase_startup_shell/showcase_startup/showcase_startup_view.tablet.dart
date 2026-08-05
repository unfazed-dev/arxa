import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_startup_viewmodel.dart';

class ShowcaseStartupViewTablet
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseStartupView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
