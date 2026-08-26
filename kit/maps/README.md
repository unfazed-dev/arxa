# arxa_kit_maps

Plugin-neutral maps port for arxa_kit apps. App code renders `ArxaKitMapView`
and depends only on Kit-owned value types (`ArxaKitLatLng`, `ArxaKitCameraPosition`,
`ArxaKitMapMarker`, `ArxaKitMapConfig`) — never on a map SDK.

## Providers

| Kind | Backend | Status |
| --- | --- | --- |
| `google` | google_maps_flutter | **Wired** — default on Android, web, desktop |
| `apple` | apple_maps_flutter | **Wired** — default on iOS (no API key) |
| `openStreetMap` | flutter_map | **Wired** — pure Dart, no key, simulator/web-testable |
| `mapbox` | flutter_map + Mapbox raster tiles | **Wired** — pure Dart, public `pk.*` token |

Backend selection is `arxaKitDefaultProviderFor(defaultTargetPlatform)`; pass
`provider:` to `ArxaKitMapView` to force one.

### OpenStreetMap

```dart
ArxaKitOpenStreetMapProvider(
  // REQUIRED by the OSM tile-usage policy (generic user agents are blocked)
  // — pass the host app's real package ID.
  userAgentPackageName: 'com.example.myapp',
)
```

Attribution is always rendered (`SimpleAttributionWidget`), and flutter_map
caches tiles itself (built-in since 8.2), satisfying the other two OSM
tile-usage-policy requirements. `ArxaKitMapConfig.mapType` is ignored — the
standard OSM tile server ships one style.

### Mapbox

flutter_map + Mapbox **raster tiles** — deliberately not the native
`mapbox_maps_flutter` SDK (which needs a secret `sk.*` downloads token in
~/.netrc and platform setup). A public `pk.*` token rides in the tile URL
against the 512px retina endpoint, so it runs on simulators, emulators, and
web with zero native config.

```dart
// flutter run --dart-define=MAPBOX_PUBLIC_TOKEN=pk....
ArxaKitMapboxProvider(
  accessToken: const String.fromEnvironment('MAPBOX_PUBLIC_TOKEN'),
  userAgentPackageName: 'com.example.myapp',
)
```

Never hardcode the token — the `MAPBOX_PUBLIC_TOKEN` entry in
`config/credentials.catalog.json` is the publishable key this provider
uses; the optional `MAPBOX_SECRET_TOKEN` entry is NOT needed here.
`ArxaKitMapConfig.mapType` selects the Mapbox style (normal → streets-v12,
satellite → satellite-v9, hybrid → satellite-streets-v12,
terrain → outdoors-v12).

### flutter_map limitations (OSM + Mapbox providers)

No flutter_map equivalent exists for `myLocationEnabled`,
`zoomControlsEnabled`, `compassEnabled`, or camera `tilt` — those
`ArxaKitMapConfig` fields are honored only by the native Google/Apple
providers. `animateCamera` jumps (no animated camera API in flutter_map
core).

## Usage

```dart
import 'package:arxa_kit_maps/arxa_kit_maps.dart';

ArxaKitMapView(
  config: const ArxaKitMapConfig(
    initialCameraPosition: ArxaKitCameraPosition(
      target: ArxaKitLatLng(-33.8688, 151.2093),
      zoom: 12,
    ),
    markers: {
      ArxaKitMapMarker(
        id: 'office',
        position: ArxaKitLatLng(-33.8688, 151.2093),
        title: 'HQ',
      ),
    },
  ),
  onMapCreated: (controller) =>
      controller.animateCamera(const ArxaKitCameraPosition(
    target: ArxaKitLatLng(-37.8136, 144.9631),
  )),
)
```

Markers are declarative (rebuild with a new `markers` set);
`ArxaKitMapController` handles post-creation camera moves only.

## Host-app platform setup

- **Google Maps** requires an API key:
  - Android: `com.google.android.geo.API_KEY` meta-data in
    `AndroidManifest.xml`
  - iOS (only if forcing Google there): `GMSServices.provideAPIKey` in
    `AppDelegate`
  - Web: Maps JS script tag in `index.html`
- **Apple Maps**: no key; MapKit entitlement handled by the plugin.

## Testing

```dart
import 'package:arxa_kit_maps/arxa_kit_testing.dart';

final fake = FakeArxaKitMapProvider();          // captures built configs
fake.controller;                          // RecordingArxaKitMapController
```

For widget tests against the real OSM/Mapbox providers, inject a fake
`TileProvider` (one that serves in-memory images) so no HTTP happens — see
`test/arxa_kit_tiled_providers_test.dart` for the pattern.

## Maintenance notes

- `apple_maps_flutter` publishes slowly (17+ months between releases at
  wiring time). If it breaks on a future Flutter, point iOS at
  `ArxaKitGoogleMapsProvider` in `arxaKitDefaultProviderFor` until fixed.
- Standalone by design: no dependency on stacked, stacked_services, or
  arxa_kit core.
