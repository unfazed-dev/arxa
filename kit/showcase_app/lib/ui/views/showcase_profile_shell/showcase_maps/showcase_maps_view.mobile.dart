import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_maps/appbox_kit_maps.dart';
import 'package:ui_library/ui_library.dart';

import 'showcase_maps_viewmodel.dart';

/// Maps showcase — one KitMapView backed by the viewmodel's provider
/// (OpenStreetMap by default, Mapbox raster tiles when a public token is
/// dart-defined). Pure-Dart backends: this runs identically on simulator,
/// emulator, desktop, and web.
class ShowcaseMapsViewMobile extends ViewModelWidget<ShowcaseMapsViewModel> {
  const ShowcaseMapsViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMapsViewModel viewModel) {
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Maps',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(kSize16),
            child: Text(
              'Backend: ${viewModel.backendLabel}'
              '${viewModel.mapboxAvailable ? '' : ' — pass --dart-define=MAPBOX_PUBLIC_TOKEN=pk.... to run the same KitMapView on Mapbox tiles.'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: KitMapView(
              config: viewModel.config,
              provider: viewModel.provider,
            ),
          ),
        ],
      ),
    );
  }
}
