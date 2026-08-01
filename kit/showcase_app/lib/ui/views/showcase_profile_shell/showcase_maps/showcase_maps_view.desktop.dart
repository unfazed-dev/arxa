import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_maps_view.mobile.dart';
import 'showcase_maps_viewmodel.dart';

/// Desktop reuses the mobile surface — the map fills any form factor.
class ShowcaseMapsViewDesktop extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) =>
      const ShowcaseMapsViewMobile();
}
