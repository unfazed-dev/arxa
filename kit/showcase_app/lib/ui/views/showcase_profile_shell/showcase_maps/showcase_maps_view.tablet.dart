import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import 'showcase_maps_view.mobile.dart';
import 'showcase_maps_viewmodel.dart';

/// Tablet reuses the mobile surface — the map fills any form factor.
class ShowcaseMapsViewTablet extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) =>
      const ShowcaseMapsViewMobile();
}
