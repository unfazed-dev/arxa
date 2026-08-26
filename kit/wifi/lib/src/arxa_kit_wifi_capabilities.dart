/// What the current platform lets this kit *do* with Wi-Fi, so demo UIs can
/// label a control as "direct" vs "escorted".
///
/// On iOS and modern Android an app cannot toggle the Wi-Fi radio or silently
/// join a network; the only honest affordance is to deep-link the user into
/// the system Settings screen. These flags let the UI render the right control
/// (a switch vs a "Open Settings" button) without hard-coding platform checks.
class ArxaKitWifiCapabilities {
  const ArxaKitWifiCapabilities({
    required this.canControlAdapter,
    required this.canJoinNetwork,
    required this.canReadNetworkInfo,
  });

  /// True only where the OS exposes a programmatic enable/disable API.
  /// `false` on iOS and Android 10+ — use the settings escort instead.
  final bool canControlAdapter;

  /// True where the app may programmatically join a specified network.
  final bool canJoinNetwork;

  /// True where SSID/BSSID/IP reads are possible (still subject to a runtime
  /// location-permission grant).
  final bool canReadNetworkInfo;

  /// The realistic capability set for iOS / modern Android: observe and
  /// escort only.
  static const escortOnly = ArxaKitWifiCapabilities(
    canControlAdapter: false,
    canJoinNetwork: false,
    canReadNetworkInfo: true,
  );
}
