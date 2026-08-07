import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_viewmodel.dart';

class ShowcaseUnknownShellViewMobile
    extends ViewModelWidget<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownShellViewModel viewModel) {
    return const NestedRouter();
  }
}
