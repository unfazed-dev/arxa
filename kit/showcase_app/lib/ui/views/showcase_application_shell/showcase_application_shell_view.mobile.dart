import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/widgets/showcase_application_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_viewmodel.dart';

class ShowcaseApplicationShellViewMobile extends ViewModelWidget<ShowcaseApplicationShellViewModel> {
  const ShowcaseApplicationShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseApplicationShellViewModel viewModel) {
    return const ShowcaseApplicationTabHostWidget();
  }
}
