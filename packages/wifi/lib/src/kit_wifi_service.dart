import 'kit_wifi_capabilities.dart';
import 'kit_wifi_network.dart';
import 'kit_wifi_state.dart';

/// Thrown when the caller invokes an adapter-control operation the current
/// platform does not support (e.g. `requestEnable` on iOS).
///
/// Catching this is the UI's cue to fall back to the settings escort
/// (`KitWifiService.openSettings`).
class KitWifiUnsupportedError extends UnsupportedError {
  KitWifiUnsupportedError(super.message);
}

/// Port for observing Wi-Fi state and escorting the user to Wi-Fi settings.
///
/// The escort contract: adapter state always comes from the live OS stream
/// ([stateChanges]) — never from cached UI state. Where the platform cannot
/// control the adapter ([KitWifiCapabilities.canControlAdapter] is `false`),
/// [requestEnable] throws [KitWifiUnsupportedError] and the UI must call
/// [openSettings] instead.
abstract interface class KitWifiService {
  /// A live stream of Wi-Fi connectivity state from the OS.
  ///
  /// Emits on every connectivity change. See [KitWifiState] for the
  /// reachability-not-radio-power caveat.
  Stream<KitWifiState> get stateChanges;

  /// A one-shot read of the current [KitWifiState].
  Future<KitWifiState> currentState();

  /// Best-effort details of the associated network, or `null` if none / not
  /// permitted. Requires location permission on recent OS versions.
  Future<KitWifiNetwork?> currentNetwork();

  /// What this platform allows (adapter control, join, info reads).
  KitWifiCapabilities get capabilities;

  /// Asks the OS to enable Wi-Fi.
  ///
  /// Throws [KitWifiUnsupportedError] where
  /// [KitWifiCapabilities.canControlAdapter] is `false` (iOS, modern Android).
  /// Callers should catch it and fall back to [openSettings].
  Future<void> requestEnable();

  /// Deep-links the user into the system Wi-Fi settings screen.
  ///
  /// Returns `true` if a settings surface was opened. This is the escort
  /// recovery path when the adapter cannot be controlled programmatically.
  Future<bool> openSettings();
}
