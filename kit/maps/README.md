# appbox_kit_maps

Plugin-neutral maps port for appbox_kit apps. App code renders `KitMapView`
and depends only on Kit-owned value types (`KitLatLng`, `KitCameraPosition`,
`KitMapMarker`, `KitMapConfig`) — never on a map SDK.

## Providers

| Kind | Backend | Status |
| --- | --- | --- |
| `google` | google_maps_flutter | **Wired** — default on Android, web, desktop |
| `apple` | apple_maps_flutter | **Wired** — default on iOS (no API key) |
| `openStreetMap` | flutter_map (planned) | Stub — throws `UnimplementedError` |
| `mapbox` | mapbox_maps_flutter (planned) | Stub — throws `UnimplementedError` |

Backend selection is `defaultProviderFor(defaultTargetPlatform)`; pass
`provider:` to `KitMapView` to force one.

Stubs are **not** dependencies — a host that never opts into OSM/Mapbox
pulls neither package. Each stub's TODO names its target package.

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

## Maintenance notes

- `apple_maps_flutter` publishes slowly (17+ months between releases at
  wiring time). If it breaks on a future Flutter, point iOS at
  `GoogleMapsProvider` in `defaultProviderFor` until fixed.
- Standalone by design: no dependency on stacked, stacked_services, or
  appbox_kit core.
