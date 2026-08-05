import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewTablet
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseSearchView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
