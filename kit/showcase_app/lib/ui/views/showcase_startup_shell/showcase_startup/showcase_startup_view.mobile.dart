import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/widgets/showcase_startup_widgets/widgets.dart';

import 'showcase_startup_viewmodel.dart';

class ShowcaseStartupViewMobile
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const ShowcaseStartupLoadingWidget();
  }
}
