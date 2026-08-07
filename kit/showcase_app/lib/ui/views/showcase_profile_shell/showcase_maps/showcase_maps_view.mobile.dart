import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

/// Maps showcase — one AppBoxKitMapView backed by the viewmodel's provider
/// (OpenStreetMap by default, Mapbox raster tiles when a public token is
/// dart-defined). Pure-Dart backends: this runs identically on simulator,
/// emulator, desktop, and web.
class ShowcaseMapsViewMobile extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) {
    return ShowcaseMapsBodyWidget(viewModel: viewModel);
  }
}
