/// The maps demo's viewmodel (route `/showcase/profile/maps`). A viewmodel is
/// actions in and streams out: the view calls methods when the user does
/// something, and reads getters when something changed. The viewmodel never
/// touches the view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the maps demo. It builds the plugin-neutral
/// map configuration — provider, camera position, and markers — from
/// compile-time constants, choosing OpenStreetMap by default or Mapbox raster
/// tiles when a token is passed. The view reads the config; the viewmodel
/// never mutates it.
///
/// Requirements:
/// 1. [Backend selection] — profile-and-gallery-demos.gallery.view-the-maps-demo
/// The map uses OpenStreetMap by default, or Mapbox raster tiles when a token is provided.
/// 2. [Demo config] — profile-and-gallery-demos.gallery.view-the-maps-demo
/// The demo map centers on London with two markers — London Eye and Tower Bridge.
///
/// Relationships:
///
///      ┌────────────────┐
///      │ maps demo view │
///      └────────────────┘
///      ┌────────────────┐
///      │ maps viewmodel │
///      └────────────────┘
///  ════════ abxAction ════════
///
///  No streams, actions, or commands — the viewmodel is read-only config.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_maps/showcase_maps_viewmodel.dart
library;

import 'package:arxa_kit_maps/arxa_kit_maps.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseMapsViewModel extends BaseViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  /// [1. Backend selection] The package id for the map provider's user agent.
  static const _packageId = 'com.arxakit.arxa_kit_showcase_app';

  /// [1. Backend selection] The Mapbox token, empty when not provided.
  static const _mapboxToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  // ── Initial state ─────────────────────────────────────────────────────────

  /// [1. Backend selection] Whether a Mapbox token was provided at compile time.
  bool get mapboxAvailable => _mapboxToken.isNotEmpty;

  /// [1. Backend selection] The human-readable label for the active backend.
  String get backendLabel =>
      mapboxAvailable ? 'Mapbox raster tiles' : 'OpenStreetMap';

  /// [1. Backend selection] The provider — Mapbox when a token exists, otherwise
  /// OpenStreetMap. The same ArxaKitMapView renders both.
  ArxaKitMapProvider get provider => mapboxAvailable
      ? ArxaKitMapboxProvider(
          accessToken: _mapboxToken,
          userAgentPackageName: _packageId,
        )
      : ArxaKitOpenStreetMapProvider(userAgentPackageName: _packageId);

  /// [2. Demo config] The camera position and markers for the demo map.
  ArxaKitMapConfig get config => ArxaKitMapConfig(
        initialCameraPosition: const ArxaKitCameraPosition(
          target: ArxaKitLatLng(51.5074, -0.1278), // London
          zoom: 11,
        ),
        markers: {
          const ArxaKitMapMarker(
            id: 'london-eye',
            position: ArxaKitLatLng(51.5033, -0.1196),
            title: 'London Eye',
          ),
          const ArxaKitMapMarker(
            id: 'tower-bridge',
            position: ArxaKitLatLng(51.5055, -0.0754),
            title: 'Tower Bridge',
          ),
        },
      );
}
