import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

/// appbox_kit_maps showcase — the plugin-neutral KitMapView on
/// OpenStreetMap (no key), flipping to Mapbox raster tiles when
/// `--dart-define=MAPBOX_PUBLIC_TOKEN` is provided.
class ShowcaseMapsView extends StackedView<ShowcaseMapsViewModel> {
  const ShowcaseMapsView({super.key});

  @override
  Widget builder(
    BuildContext context,
    ShowcaseMapsViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseMapsViewMobile(),
      tablet: (_) => const ShowcaseMapsViewTablet(),
      desktop: (_) => const ShowcaseMapsViewDesktop(),
    );
  }

  @override
  ShowcaseMapsViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseMapsViewModel();
}
