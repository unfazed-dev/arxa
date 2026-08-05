import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/widgets/showcase_unknown_widgets/widgets.dart';

import 'showcase_unknown_viewmodel.dart';

class ShowcaseUnknownViewTablet
    extends ViewModelWidget<ShowcaseUnknownViewModel> {
  const ShowcaseUnknownViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownViewModel viewModel) {
    return const ShowcaseUnknownBodyWidget();
  }
}
