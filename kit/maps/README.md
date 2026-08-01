# appbox_kit_maps

Plugin-neutral maps port for appbox_kit apps. App code renders `KitMapView`
and depends only on Kit-owned value types (`KitLatLng`, `KitCameraPosition`,
`KitMapMarker`, `KitMapConfig`) — never on a map SDK.

## Providers

| Kind | Backend | Status |
| --- | --- | --- |
| `google` | google_maps_flutter | **Wired** — default on Android, web, desktop |
| `apple` | apple_maps_flutter | **Wired** — default on iOS (no API key) |
| `openStreetMap` | flutter_map | **Wired** — pure Dart, no key, simulator/web-testable |
| `mapbox` | flutter_map + Mapbox raster tiles | **Wired** — pure Dart, public `pk.*` token |

Backend selection is `defaultProviderFor(defaultTargetPlatform)`; pass
`provider:` to `KitMapView` to force one.

### OpenStreetMap

```dart
OpenStreetMapProvider(
  // REQUIRED by the OSM tile-usage policy (generic user agents are blocked)
  // — pass the host app's real package ID.
  userAgentPackageName: 'com.example.myapp',
)
```

Attribution is always rendered (`SimpleAttributionWidget`), and flutter_map
caches tiles itself (built-in since 8.2), satisfying the other two OSM
tile-usage-policy requirements. `KitMapConfig.mapType` is ignored — the
standard OSM tile server ships one style.

### Mapbox

flutter_map + Mapbox **raster tiles** — deliberately not the native
`mapbox_maps_flutter` SDK (which needs a secret `sk.*` downloads token in
~/.netrc and platform setup). A public `pk.*` token rides in the tile URL
against the 512px retina endpoint, so it runs on simulators, emulators, and
web with zero native config.

```dart
// flutter run --dart-define=MAPBOX_PUBLIC_TOKEN=pk....
MapboxProvider(
  accessToken: const String.fromEnvironment('MAPBOX_PUBLIC_TOKEN'),
  userAgentPackageName: 'com.example.myapp',
)
```

Never hardcode the token — the `MAPBOX_PUBLIC_TOKEN` entry in
`config/credentials.catalog.json` is the publishable key this provider
uses; the optional `MAPBOX_SECRET_TOKEN` entry is NOT needed here.
`KitMapConfig.mapType` selects the Mapbox style (normal → streets-v12,
satellite → satellite-v9, hybrid → satellite-streets-v12,
terrain → outdoors-v12).

### flutter_map limitations (OSM + Mapbox providers)

No flutter_map equivalent exists for `myLocationEnabled`,
`zoomControlsEnabled`, `compassEnabled`, or camera `tilt` — those
`KitMapConfig` fields are honored only by the native Google/Apple
providers. `animateCamera` jumps (no animated camera API in flutter_map
core).

## Usage

```dart
import 'package:appbox_kit_maps/appbox_kit_maps.dart';

KitMapView(
  config: const KitMapConfig(
    initialCameraPosition: KitCameraPosition(
      target: KitLatLng(-33.8688, 151.2093),
      zoom: 12,
    ),
    markers: {
      KitMapMarker(
        id: 'office',
        position: KitLatLng(-33.8688, 151.2093),
        title: 'HQ',
      ),
    },
  ),
  onMapCreated: (controller) =>
      controller.animateCamera(const KitCameraPosition(
    target: KitLatLng(-37.8136, 144.9631),
  )),
)
```

Markers are declarative (rebuild with a new `markers` set);
`KitMapController` handles post-creation camera moves only.

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
import 'package:appbox_kit_maps/testing.dart';

final fake = FakeMapProvider();          // captures built configs
fake.controller;                          // RecordingMapController
```

For widget tests against the real OSM/Mapbox providers, inject a fake
`TileProvider` (one that serves in-memory images) so no HTTP happens — see
`test/tiled_providers_test.dart` for the pattern.

## Maintenance notes

- `apple_maps_flutter` publishes slowly (17+ months between releases at
  wiring time). If it breaks on a future Flutter, point iOS at
  `GoogleMapsProvider` in `defaultProviderFor` until fixed.
- Standalone by design: no dependency on stacked, stacked_services, or
  appbox_kit core.
