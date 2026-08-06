import 'appbox_kit_wifi_capabilities.dart';
import 'appbox_kit_wifi_network.dart';
import 'appbox_kit_wifi_state.dart';

/// Thrown when the caller invokes an adapter-control operation the current
/// platform does not support (e.g. `requestEnable` on iOS).
///
/// Catching this is the UI's cue to fall back to the settings escort
/// (`AppBoxKitWifiService.openSettings`).
class AppBoxKitWifiUnsupportedError extends UnsupportedError {
  AppBoxKitWifiUnsupportedError(super.message);
}

/// Port for observing Wi-Fi state and escorting the user to Wi-Fi settings.
///
/// The escort contract: adapter state always comes from the live OS stream
/// ([stateChanges]) — never from cached UI state. Where the platform cannot
/// control the adapter ([AppBoxKitWifiCapabilities.canControlAdapter] is `false`),
/// [requestEnable] throws [AppBoxKitWifiUnsupportedError] and the UI must call
/// [openSettings] instead.
abstract interface class AppBoxKitWifiService {
  /// A live stream of Wi-Fi connectivity state from the OS.
  ///
  /// Emits on every connectivity change. See [AppBoxKitWifiState] for the
  /// reachability-not-radio-power caveat.
  Stream<AppBoxKitWifiState> get stateChanges;

  /// A one-shot read of the current [AppBoxKitWifiState].
  Future<AppBoxKitWifiState> currentState();

  /// Best-effort details of the associated network, or `null` if none / not
  /// permitted. Requires location permission on recent OS versions.
  Future<AppBoxKitWifiNetwork?> currentNetwork();

  /// What this platform allows (adapter control, join, info reads).
  AppBoxKitWifiCapabilities get capabilities;

  /// Asks the OS to enable Wi-Fi.
  ///
  /// Throws [AppBoxKitWifiUnsupportedError] where
  /// [AppBoxKitWifiCapabilities.canControlAdapter] is `false` (iOS, modern Android).
  /// Callers should catch it and fall back to [openSettings].
  Future<void> requestEnable();

  /// Deep-links the user into the system Wi-Fi settings screen.
  ///
  /// Returns `true` if a settings surface was opened. This is the escort
  /// recovery path when the adapter cannot be controlled programmatically.
  Future<bool> openSettings();
}
