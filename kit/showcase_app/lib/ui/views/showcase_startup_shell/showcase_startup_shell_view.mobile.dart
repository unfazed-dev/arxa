import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup_shell_viewmodel.dart';

class ShowcaseStartupShellViewMobile
    extends ViewModelWidget<ShowcaseStartupShellViewModel> {
  const ShowcaseStartupShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupShellViewModel viewModel) {
    return const NestedRouter();
  }
}
