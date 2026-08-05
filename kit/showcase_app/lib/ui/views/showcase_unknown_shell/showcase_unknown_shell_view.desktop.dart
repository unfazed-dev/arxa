import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_unknown_shell_viewmodel.dart';

class ShowcaseUnknownShellViewDesktop
    extends ViewModelWidget<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownShellViewModel viewModel) {
    return const NestedRouter();
  }
}
