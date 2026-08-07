import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/widgets/showcase_startup_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_viewmodel.dart';

class ShowcaseStartupViewMobile
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const ShowcaseStartupLoadingWidget();
  }
}
