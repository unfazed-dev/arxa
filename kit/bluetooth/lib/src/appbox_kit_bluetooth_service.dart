import 'appbox_kit_bluetooth_adapter_state.dart';
import 'appbox_kit_bluetooth_capabilities.dart';

/// Thrown when the caller invokes an adapter-control operation the current
/// platform does not support (e.g. `requestEnable` on iOS). Catching this is
/// the UI's cue to fall back to the settings escort.
class AppBoxKitBluetoothUnsupportedError extends UnsupportedError {
  AppBoxKitBluetoothUnsupportedError(super.message);
}

/// Port for observing the Bluetooth adapter state and escorting the user.
///
/// The escort contract: [adapterState] always comes from the live OS stream —
/// never cached UI state. Where [AppBoxKitBluetoothCapabilities.canControlAdapter]
/// is `false`, [requestEnable] throws [AppBoxKitBluetoothUnsupportedError] and the
/// UI must call [openSettings] instead.
///
/// Scanning and GATT (connect/read/write/notify) are intentionally **not**
/// part of this port — see `AppBoxKitBluetoothScanner` and `AppBoxKitBluetoothGattClient`.
abstract interface class AppBoxKitBluetoothService {
  /// A live stream of adapter power state from the OS.
  Stream<AppBoxKitBluetoothAdapterState> get adapterState;

  /// A one-shot read of the current adapter state.
  Future<AppBoxKitBluetoothAdapterState> currentAdapterState();

  /// What this platform allows (adapter control).
  AppBoxKitBluetoothCapabilities get capabilities;

  /// Asks the OS to enable Bluetooth.
  ///
  /// On Android this shows the system enable dialog. Throws
  /// [AppBoxKitBluetoothUnsupportedError] where
  /// [AppBoxKitBluetoothCapabilities.canControlAdapter] is `false` (iOS).
  Future<void> requestEnable();

  /// Deep-links the user into the system Bluetooth settings screen.
  /// Returns `true` if a settings surface was opened.
  Future<bool> openSettings();
}
