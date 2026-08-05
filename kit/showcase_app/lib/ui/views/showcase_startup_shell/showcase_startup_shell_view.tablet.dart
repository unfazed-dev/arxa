import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_startup_shell_viewmodel.dart';

class ShowcaseStartupShellViewTablet
    extends ViewModelWidget<ShowcaseStartupShellViewModel> {
  const ShowcaseStartupShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupShellViewModel viewModel) {
    return const NestedRouter();
  }
}
