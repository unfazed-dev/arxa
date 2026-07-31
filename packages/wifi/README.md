# stacked_kit_wifi

Plugin-neutral **port** for observing Wi-Fi state and escorting the user to
Wi-Fi settings. The app depends on `KitWifiService`; the plumbing
(`connectivity_plus`, `network_info_plus`, `app_settings`) stays behind it.

Phase: **1 — observation + escort implemented**; adapter control and
network-join are stubs (no mobile OS exposes them).

## Scope

- `KitWifiState` — `connected` / `disconnected` / `unknown`.
  **Reflects connectivity/reachability, not radio power.** Mobile OSes do not
  expose the Wi-Fi adapter's on/off state; `connected` implies the adapter is
  on, but `disconnected` does not prove it is off.
- `KitWifiNetwork` — best-effort `ssid` / `bssid` / `ipAddress` (all nullable;
  location-permission gated by the OS).
- `KitWifiCapabilities` — `canControlAdapter` / `canJoinNetwork` /
  `canReadNetworkInfo`, so demo UIs can label a control **direct** vs
  **escorted**. `KitWifiCapabilities.escortOnly` is the iOS/modern-Android set.
- `KitWifiService` — the port:
  - `stateChanges` — **live OS stream** (the implemented priority).
  - `currentState()` / `currentNetwork()`.
  - `requestEnable()` — throws `KitWifiUnsupportedError` where the adapter is
    uncontrollable.
  - `openSettings()` — the escort deep-link.
- `ConnectivityKitWifiService` — production binding.

### Why connectivity_plus for the stream

`network_info_plus` is request/response only — it has no stream, and polling
`getWifiName()` would both violate the "real OS stream, never cached" contract
and misreport "off" whenever location permission is denied (SSID reads return
`null`). The live `Stream<KitWifiState>` therefore comes from
`connectivity_plus` (Android `ConnectivityManager` / iOS `NWPathMonitor`);
`network_info_plus` is used only for the on-demand SSID/IP read.

## Backing packages (verified pub.dev 2026-07-14)

- `connectivity_plus` **^7.2.0** — stream source.
- `network_info_plus` **^8.2.0** — SSID/BSSID/IP.
- `app_settings` **^7.0.0** — Wi-Fi settings deep-link.

## Testing

`package:stacked_kit_wifi/testing.dart` exports `FakeKitWifiService`: drive the
stream with `emit`, set `currentNetwork` with `setNetwork`, and assert the
escort via `openSettingsCallCount` / `requestEnableCallCount`. `requestEnable`
throws by default (adapter uncontrollable) so the escort branch is exercisable.

## Non-goals (stubs)

- **Direct adapter control** — `requestEnable()` throws `KitWifiUnsupportedError`.
- **Join a network** — not implemented; no cross-platform OS API.
- No path dependency on `stacked_kit_permissions` (or any kit). The SSID-read
  location-permission dependency is wired by the downstream reconciliation pass.
