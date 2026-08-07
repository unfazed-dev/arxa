import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/widgets/showcase_unknown_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_viewmodel.dart';

class ShowcaseUnknownViewMobile
    extends ViewModelWidget<ShowcaseUnknownViewModel> {
  const ShowcaseUnknownViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownViewModel viewModel) {
    return const ShowcaseUnknownBodyWidget();
  }
}
