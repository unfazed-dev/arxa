import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_profile_viewmodel.dart';

class ShowcaseProfileViewDesktop
    extends ViewModelWidget<ShowcaseProfileViewModel> {
  const ShowcaseProfileViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseProfileView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
