import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_profile_viewmodel.dart';

class ShowcaseProfileViewTablet
    extends ViewModelWidget<ShowcaseProfileViewModel> {
  const ShowcaseProfileViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseProfileView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
