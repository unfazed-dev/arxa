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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

/// Desktop reuses the mobile surface — the map fills any form factor.
class ShowcaseMapsViewDesktop extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) =>
      const ShowcaseMapsViewMobile();
}
