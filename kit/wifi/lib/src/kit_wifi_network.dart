/// Best-effort details about the currently associated Wi-Fi network.
///
/// Every field is nullable: modern iOS and Android gate SSID/BSSID reads
/// behind location permission (and, on iOS, entitlements), so a `null` [ssid]
/// on a [KitWifiState.connected] device usually means "permission not
/// granted", not "no network". Consumers should treat the whole object as a
/// hint, never as authoritative connection state.
class KitWifiNetwork {
  const KitWifiNetwork({
    this.ssid,
    this.bssid,
    this.ipAddress,
  });

  /// The network name, e.g. `"HomeWiFi"`. Requires location permission on
  /// recent OS versions; `null` when unavailable.
  final String? ssid;

  /// The access-point MAC address. Same permission gate as [ssid].
  final String? bssid;

  /// The device's IPv4 address on this network.
  final String? ipAddress;

  @override
  String toString() =>
      'KitWifiNetwork(ssid: $ssid, bssid: $bssid, ipAddress: $ipAddress)';
}
