/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the maps demo — the plugin-neutral
/// AppBoxKitMapView on OpenStreetMap by default (no key), flipping to Mapbox
/// raster tiles when a public token is dart-defined. The tablet and desktop
/// variants reuse the mobile surface (the map fills any form factor).
///
/// Requirements:
/// 1. [Map view] — view-the-maps-demo
/// A plugin-neutral map view backed by the viewmodel's provider.
/// 2. [OpenStreetMap default] — view-the-maps-demo
/// OpenStreetMap tiles by default, with no key required.
/// 3. [Mapbox opt-in] — view-the-maps-demo
/// Mapbox raster tiles when a public token is dart-defined.
///
/// Relationships:
///
///      ┌───────────┐
///      │ maps view │
///      └───────────┘
///            ▲ STRM
///      [1-4]
///   ┌────────────────┐
///   │ maps viewmodel │
///   └────────────────┘
/// ════════ abxAction ════════
///
///   streams (STRM)
///     1. config
///     2. provider
///     3. backendLabel
///     4. mapboxAvailable
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

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
