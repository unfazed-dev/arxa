import 'kit_bluetooth_adapter_state.dart';
import 'kit_bluetooth_capabilities.dart';

/// Thrown when the caller invokes an adapter-control operation the current
/// platform does not support (e.g. `requestEnable` on iOS). Catching this is
/// the UI's cue to fall back to the settings escort.
class KitBluetoothUnsupportedError extends UnsupportedError {
  KitBluetoothUnsupportedError(super.message);
}

/// Port for observing the Bluetooth adapter state and escorting the user.
///
/// The escort contract: [adapterState] always comes from the live OS stream —
/// never cached UI state. Where [KitBluetoothCapabilities.canControlAdapter]
/// is `false`, [requestEnable] throws [KitBluetoothUnsupportedError] and the
/// UI must call [openSettings] instead.
///
/// Scanning and GATT (connect/read/write/notify) are intentionally **not**
/// part of this port — see `KitBluetoothScanner` and `KitBluetoothGattClient`.
abstract interface class KitBluetoothService {
  /// A live stream of adapter power state from the OS.
  Stream<KitBluetoothAdapterState> get adapterState;

  /// A one-shot read of the current adapter state.
  Future<KitBluetoothAdapterState> currentAdapterState();

  /// What this platform allows (adapter control).
  KitBluetoothCapabilities get capabilities;

  /// Asks the OS to enable Bluetooth.
  ///
  /// On Android this shows the system enable dialog. Throws
  /// [KitBluetoothUnsupportedError] where
  /// [KitBluetoothCapabilities.canControlAdapter] is `false` (iOS).
  Future<void> requestEnable();

  /// Deep-links the user into the system Bluetooth settings screen.
  /// Returns `true` if a settings surface was opened.
  Future<bool> openSettings();
}
