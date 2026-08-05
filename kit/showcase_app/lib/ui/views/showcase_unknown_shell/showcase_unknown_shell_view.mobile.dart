import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_unknown_shell_viewmodel.dart';

class ShowcaseUnknownShellViewMobile
    extends ViewModelWidget<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownShellViewModel viewModel) {
    return const NestedRouter();
  }
}
