import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_search_shell_viewmodel.dart';

class ShowcaseSearchShellViewTablet
    extends ViewModelWidget<ShowcaseSearchShellViewModel> {
  const ShowcaseSearchShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseSearchShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
