import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_home_viewmodel.dart';

class ShowcaseHomeViewDesktop extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseHomeView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
