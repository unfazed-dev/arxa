import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_unknown_shell_viewmodel.dart';

class ShowcaseUnknownShellViewTablet
    extends ViewModelWidget<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownShellViewModel viewModel) {
    return const NestedRouter();
  }
}
