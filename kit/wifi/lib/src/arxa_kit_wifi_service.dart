import 'arxa_kit_wifi_capabilities.dart';
import 'arxa_kit_wifi_network.dart';
import 'arxa_kit_wifi_state.dart';

/// Thrown when the caller invokes an adapter-control operation the current
/// platform does not support (e.g. `requestEnable` on iOS).
///
/// Catching this is the UI's cue to fall back to the settings escort
/// (`ArxaKitWifiService.openSettings`).
class ArxaKitWifiUnsupportedError extends UnsupportedError {
  ArxaKitWifiUnsupportedError(super.message);
}

/// Port for observing Wi-Fi state and escorting the user to Wi-Fi settings.
///
/// The escort contract: adapter state always comes from the live OS stream
/// ([stateChanges]) — never from cached UI state. Where the platform cannot
/// control the adapter ([ArxaKitWifiCapabilities.canControlAdapter] is `false`),
/// [requestEnable] throws [ArxaKitWifiUnsupportedError] and the UI must call
/// [openSettings] instead.
abstract interface class ArxaKitWifiService {
  /// A live stream of Wi-Fi connectivity state from the OS.
  ///
  /// Emits on every connectivity change. See [ArxaKitWifiState] for the
  /// reachability-not-radio-power caveat.
  Stream<ArxaKitWifiState> get stateChanges;

  /// A one-shot read of the current [ArxaKitWifiState].
  Future<ArxaKitWifiState> currentState();

  /// Best-effort details of the associated network, or `null` if none / not
  /// permitted. Requires location permission on recent OS versions.
  Future<ArxaKitWifiNetwork?> currentNetwork();

  /// What this platform allows (adapter control, join, info reads).
  ArxaKitWifiCapabilities get capabilities;

  /// Asks the OS to enable Wi-Fi.
  ///
  /// Throws [ArxaKitWifiUnsupportedError] where
  /// [ArxaKitWifiCapabilities.canControlAdapter] is `false` (iOS, modern Android).
  /// Callers should catch it and fall back to [openSettings].
  Future<void> requestEnable();

  /// Deep-links the user into the system Wi-Fi settings screen.
  ///
  /// Returns `true` if a settings surface was opened. This is the escort
  /// recovery path when the adapter cannot be controlled programmatically.
  Future<bool> openSettings();
}
