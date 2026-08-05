import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

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
