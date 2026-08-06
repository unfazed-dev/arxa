/// The observable Wi-Fi state exposed by `AppBoxKitWifiService.stateChanges`.
///
/// IMPORTANT — this reflects **connectivity/reachability, not radio power.**
/// Mobile OSes do not expose the Wi-Fi adapter's on/off state to apps, so this
/// kit reports whether the device currently has an active Wi-Fi connection
/// (via the OS connectivity stream), which it can observe. A [connected]
/// state implies the adapter is enabled; [disconnected] does **not** prove the
/// adapter is off — it may be on but not associated with a network.
enum AppBoxKitWifiState {
  /// The device has an active Wi-Fi connection.
  connected,

  /// The device has no active Wi-Fi connection (adapter may be on-but-idle or
  /// off — indistinguishable from within the app).
  disconnected,

  /// No reading yet (before the first OS event) or the platform could not
  /// report a state.
  unknown,
}
