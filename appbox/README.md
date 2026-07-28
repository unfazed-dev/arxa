# appbox

The consolidated app-box shell: **one Stacked Flutter app with full parity
across web, macOS, iOS and Android** (consolidation plan,
`docs/plans/consolidate-one-app-plus-daemon.md`, dogfood step 1). There is no
"companion" and no "remote app" — every shell is app-box with every surface.

Created once, by hand, as the honest bootstrap:

```
stacked create app appbox --template=web --platforms=web,macos,ios,android --org=com.totemlabs
```

(Bundle id `com.totemlabs.appbox`, matching the existing `app/` macOS target.)

## Ownership

- **The pipeline owns `lib/ui/**`** from the first scaffolder run onward —
  this template's views/widgets are placeholders until then. Everything
  outside `lib/ui/**` (runner folders, `lib/app/` locator/router skeleton,
  platform ceremony) is hand-maintained.
- `appboxd/` (the daemon) and the pipeline/gates/tools live outside this
  shell; this app is a client of the daemon, not a host for pipeline logic.

## Platform ceremony (LAN pairing + QR scanning)

Discovery and pairing die silently without these — they exist here, in the
shell, so no later pipeline run has to rediscover them.

### iOS (`ios/Runner/Info.plist`)

Ported verbatim from `companion/ios/Runner/Info.plist`. Without them Bonjour
discovery fails with `NSNetServicesErrorCode -72008`:

- `NSLocalNetworkUsageDescription` — local-network permission prompt.
- `NSBonjourServices` = `_appbox._tcp` — declares the Bonjour service type.
- `NSCameraUsageDescription` — camera for scanning the desktop's pairing QR.

### Android (`android/app/src/main/AndroidManifest.xml`)

Derived from the same requirements (plan 12 was iOS-only; this is the minimal
Android equivalent):

- `INTERNET` — LAN sockets to the desktop daemon.
- `ACCESS_NETWORK_STATE` — reachability checks before pairing.
- `CAMERA` — scan the desktop's pairing QR code (runtime permission).

Deliberately omitted: `CHANGE_WIFI_MULTICAST_STATE` — mDNS via `NsdManager`
needs no extra permission; it's only required for raw UDP multicast. Add it
when a chosen discovery plugin actually requires it.

### macOS / web

No ceremony yet. macOS sandbox entitlements (network client/server) land with
the daemon-embedding work; web reaches the daemon over plain HTTP(S) on LAN.

## Verify

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze   # clean
flutter test      # all tests pass
flutter build web --release
flutter build macos --release   # Xcode required
```

Template fixes applied on creation (stacked v1.15.5 template bugs, not
app-box logic): quoted the pubspec description, replaced deprecated
`Matrix4.scale/translate` and `tester.binding.window` calls, dropped `const`
from `HomeViewRoute()`, pointed the golden test at the mock service
registration, and generated the missing golden file.
