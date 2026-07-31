import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_home_viewmodel.dart';

class ShowcaseHomeViewTablet extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseHomeView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
