import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
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
