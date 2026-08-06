import 'package:app_settings/app_settings.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'appbox_kit_wifi_capabilities.dart';
import 'appbox_kit_wifi_network.dart';
import 'appbox_kit_wifi_service.dart';
import 'appbox_kit_wifi_state.dart';

/// Production [AppBoxKitWifiService].
///
/// The implemented priority is **adapter-state observation + escort**:
/// - [stateChanges] / [currentState] come from the live `connectivity_plus`
///   stream (the real OS connectivity signal, never cached UI state).
/// - [currentNetwork] reads SSID/BSSID/IP via `network_info_plus`.
/// - [openSettings] deep-links to Wi-Fi settings via `app_settings`.
///
/// Adapter control ([requestEnable]) is unsupported on the platforms this kit
/// targets and throws [AppBoxKitWifiUnsupportedError] — the UI escorts instead.
class ConnectivityAppBoxKitWifiService implements AppBoxKitWifiService {
  ConnectivityAppBoxKitWifiService({
    Connectivity? connectivity,
    NetworkInfo? networkInfo,
  })  : _connectivity = connectivity ?? Connectivity(),
        _networkInfo = networkInfo ?? NetworkInfo();

  final Connectivity _connectivity;
  final NetworkInfo _networkInfo;

  @override
  AppBoxKitWifiCapabilities get capabilities => AppBoxKitWifiCapabilities.escortOnly;

  @override
  Stream<AppBoxKitWifiState> get stateChanges =>
      _connectivity.onConnectivityChanged.map(_toState);

  @override
  Future<AppBoxKitWifiState> currentState() async {
    return _toState(await _connectivity.checkConnectivity());
  }

  @override
  Future<AppBoxKitWifiNetwork?> currentNetwork() async {
    final ssid = await _networkInfo.getWifiName();
    final bssid = await _networkInfo.getWifiBSSID();
    final ip = await _networkInfo.getWifiIP();
    if (ssid == null && bssid == null && ip == null) return null;
    return AppBoxKitWifiNetwork(ssid: ssid, bssid: bssid, ipAddress: ip);
  }

  @override
  Future<void> requestEnable() async {
    // No cross-platform OS API enables the Wi-Fi radio on iOS or Android 10+.
    throw AppBoxKitWifiUnsupportedError(
      'Enabling Wi-Fi programmatically is not supported on this platform; '
      'call openSettings() to escort the user instead.',
    );
  }

  @override
  Future<bool> openSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    return true;
  }

  AppBoxKitWifiState _toState(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return AppBoxKitWifiState.connected;
    }
    return AppBoxKitWifiState.disconnected;
  }
}
