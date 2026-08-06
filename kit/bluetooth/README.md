# appbox_kit_bluetooth

Plugin-neutral **port** over `flutter_blue_plus`. The app depends on
`AppBoxKitBluetoothService` and Kit-prefixed value types; no `flutter_blue_plus`
types leak across the seam.

Phase: **1 — adapter observation + capability gate + escort implemented**;
scanning and GATT are full stub ports (final signatures, `UnimplementedError`).

## Scope

### Implemented (priority)

- `AppBoxKitBluetoothAdapterState` — `unknown` / `unavailable` / `unauthorized` /
  `poweredOff` / `turningOn` / `poweredOn` / `turningOff`. The production
  binding maps **every** `flutter_blue_plus` `BluetoothAdapterState` variant
  onto exactly one of these.
- `AppBoxKitBluetoothCapabilities` — `canControlAdapter`: `true` on Android
  (system enable dialog), `false` on iOS (escort). Lets demo UIs label a
  control **direct** vs **escorted**.
- `AppBoxKitBluetoothService` — the port:
  - `adapterState` — **live OS stream** (the implemented priority).
  - `currentAdapterState()`.
  - `requestEnable()` — Android system dialog; throws
    `AppBoxKitBluetoothUnsupportedError` on iOS.
  - `openSettings()` — Bluetooth settings deep-link (escort).
- `AppBoxKitFlutterBluePlusBluetoothService` — production binding.

### Stubs (phase 2)

- `AppBoxKitBluetoothScanner` — `scanResults` / `isScanning` / `startScan` /
  `stopScan`. `UnimplementedAppBoxKitBluetoothScanner` throws.
- `AppBoxKitBluetoothGattClient` — `connect` / `disconnect` / `discoverServices` /
  `read` / `write` / `setNotify` / `connectionState`.
  `UnimplementedAppBoxKitBluetoothGattClient` throws.
- Value types: `AppBoxKitBluetoothDevice`, `AppBoxKitBluetoothScanResult`,
  `AppBoxKitGattService`, `AppBoxKitGattCharacteristic`, `AppBoxKitBluetoothConnectionState`.

## Backing packages (verified pub.dev 2026-07-14)

- `flutter_blue_plus` **^2.3.10** — CoreBluetooth / android.bluetooth wrapper.
- `app_settings` **^7.0.0** — Bluetooth settings deep-link.

## Testing

`package:appbox_kit_bluetooth/appbox_kit_testing.dart` exports `FakeAppBoxKitBluetoothService`:
drive the adapter stream with `emit`, choose the capability set, and assert the
escort via `openSettingsCallCount` / `requestEnableCallCount`. On the
`escortOnly` capability set `requestEnable` throws so the escort branch is
exercisable.

## Native-first

`flutter_blue_plus` is a direct wrapper over the OS Bluetooth stacks; this
package ships no custom native code. The escort contract holds: adapter state
always comes from the live OS stream, never cached UI state.

## Non-goals

No path dependency on `appbox_kit_permissions` (or any kit). The Android 12+
`BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` runtime-permission dependency is wired by
the downstream reconciliation pass.
