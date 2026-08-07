/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the maps demo body — the app bar, the
/// backend label, and the AppBoxKitMapView backed by the viewmodel's provider
/// (OpenStreetMap by default, Mapbox raster tiles when a public token is
/// dart-defined).
///
/// Requirements:
/// 1. [Map view] — view-the-maps-demo
/// A plugin-neutral map view backed by the viewmodel's provider.
/// 2. [Backend label] — view-the-maps-demo
/// The active backend is shown, with a hint when Mapbox is not configured.
///
/// Relationships:
///
///    ┌──────────────────┐
///    │ maps body widget │
///    └──────────────────┘
///                ▲ STRM
///     [1-4]
///     ┌────────────────┐
///     │ maps viewmodel │
///     └────────────────┘
/// ════════ abxAction ════════
///
///   streams (STRM)
///     1. config
///     2. provider
///     3. backendLabel
///     4. mapboxAvailable
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_maps_body_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart';

/// Maps showcase body — the app bar, the backend label, and the
/// [AppBoxKitMapView] backed by the viewmodel's provider (OpenStreetMap by
/// default, Mapbox raster tiles when a public token is dart-defined).
class ShowcaseMapsBodyWidget extends StatelessWidget {
  const ShowcaseMapsBodyWidget({required this.viewModel, super.key});

  final ShowcaseMapsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBoxKitNativeAppBar(
        leading: AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Maps',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(abxSize16),
            child: Text(
              'Backend: ${viewModel.backendLabel}'
              '${viewModel.mapboxAvailable ? '' : ' — pass --dart-define=MAPBOX_PUBLIC_TOKEN=pk.... to run the same AppBoxKitMapView on Mapbox tiles.'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: AppBoxKitMapView(
              config: viewModel.config,
              provider: viewModel.provider,
            ),
          ),
        ],
      ),
    );
  }
}
