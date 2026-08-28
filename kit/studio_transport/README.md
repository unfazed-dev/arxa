# arxa_kit_studio_transport

iroh-backed pairing transport for arxa studio mobile. Rust core (a port of the
Tauri scaffold's `arxa/mobile/src-tauri/src/connection.rs`) bound to Dart via
**flutter_rust_bridge v2** and built by **cargokit** (vendored in `cargokit/`).

Wire contract: `arxa-studio/docs/plans/mobile-flutter-migration-spec.md`.
Architecture rationale: `arxa-studio/docs/research/iroh-flutter-strategy-2026.md`.

## What it does

- Parses the pairing QR payload `arxa-pair:<base32(json)>`
  (`{node: <iroh endpoint ticket>, token: <32-byte hex>}`).
- Dials the desktop over iroh QUIC, ALPN `arxa/studio/0`; every bidi stream
  opens with `AUTH <token> <device-name>\n` → `OK\n`.
- Runs an in-process loopback HTTP proxy (`127.0.0.1:<port>`) that bridges raw
  HTTP/1.1 to the desktop — point any Dart HTTP client at `session.proxyPort`.
- Push relay: `PUSH <session_token> <platform> <token>\n` → `OK\n`, re-sent
  automatically after every reconnect.
- Reconnect state machine with the spec's pinned constants: 15 s auth timeout,
  3 s backoff, 2 fresh-dial / 5 reconnect-dial attempts. No heartbeat frame —
  liveness is stream-level. Revocation = desktop closing/refusing AUTH →
  status `revoked` (terminal; rescan required).

## Dart API

```dart
import 'package:arxa_kit_studio_transport/arxa_kit_studio_transport.dart';

final session = await StudioTransport.connect(qrPayload, deviceName: 'My phone');
session.status.listen((s) { /* connecting/connected/reconnecting/revoked/disconnected */ });
final port = session.proxyPort;            // while connected; re-read after reconnects
await session.registerPushToken('apns', token);
await session.resume();                    // call on app foreground (iOS suspends QUIC)
await session.close();
```

`MockStudioSession` / `MockStudioTransport` (exported from the same library)
are in-memory doubles for app tests — no Rust, no network.

## iOS backgrounding

iOS suspends QUIC sockets when the app backgrounds; the old connection is
usually dead on return. Wire `AppLifecycleListener.onResume` (or equivalent)
to `session.resume()` — it supersedes the dead session and redials on the
reconnect budget (5 attempts, 3 s backoff).

## Regenerating bindings

```sh
flutter_rust_bridge_codegen generate   # from the package root; config in flutter_rust_bridge.yaml
```

Pins that must move together: `flutter_rust_bridge_codegen` (installed CLI),
`flutter_rust_bridge` in `rust/Cargo.toml`, and `flutter_rust_bridge` in
`pubspec.yaml` — all `2.13.0-beta.5`.

## Device-build caveats (recorded, not yet exercised)

Per the iroh-flutter strategy report — these bite at *app* build time, not in
this package's tests:

- **Android: 16 KB page sizes / NDK.** Google Play requires 16 KB-page-aligned
  native libs (Android 15+ on ARM64). Build with NDK **r28+** (aligns by
  default) or pass `-Wl,-z,max-page-size=16384`; verify with
  `llvm-readelf -l libarxa_studio_transport.so` (LOAD align `0x4000`).
  cargokit uses the NDK the Flutter Android build provides — pin NDK in the
  *app's* `android/app/build.gradle`.
- **iOS: static lib + symbol stripping.** The pod ships a `staticlib`; Xcode
  sees no direct symbol references from Swift/ObjC, so the FRB entry points
  would be dead-stripped. The podspec force-loads the archive
  (`OTHER_LDFLAGS: -force_load`); if pairing fails on a device with
  "symbol not found", check that flag survived the app's Podfile post-install
  hooks. Bitcode is gone since Xcode 14 — no action needed.
- **iOS simulator on Apple Silicon** needs the `aarch64-apple-ios-sim` rustup
  target; device builds need `aarch64-apple-ios`; Android needs the four
  `*-linux-android` targets. cargokit installs missing targets via rustup when
  it can.

## Layout

```
rust/                 Rust crate (arxa_studio_transport): transport core + FRB api
lib/                  Dart: StudioTransport/StudioSession wrapper + mocks
lib/src/rust/         flutter_rust_bridge generated bindings (do not edit)
cargokit/             vendored build glue (gradle plugin + CocoaPods script phase)
android/ ios/ macos/  ffi-plugin build hooks calling into cargokit
```
