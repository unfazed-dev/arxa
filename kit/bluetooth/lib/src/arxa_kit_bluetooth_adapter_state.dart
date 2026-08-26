/// Platform-neutral Bluetooth adapter power state.
///
/// Mirrors `flutter_blue_plus`'s `BluetoothAdapterState` so consumers can
/// switch on adapter state without importing the plugin. The production
/// binding maps every plugin variant onto exactly one value here.
enum ArxaKitBluetoothAdapterState {
  /// State not yet known (before the first OS event).
  unknown,

  /// The device has no Bluetooth support / hardware.
  unavailable,

  /// The app is not authorized to use Bluetooth (iOS usage prompt denied, or
  /// Android runtime permission not granted).
  unauthorized,

  /// The adapter is powered off.
  poweredOff,

  /// The adapter is transitioning to on.
  turningOn,

  /// The adapter is powered on and usable.
  poweredOn,

  /// The adapter is transitioning to off.
  turningOff;

  /// True when scanning/connecting is possible right now.
  bool get isOn => this == ArxaKitBluetoothAdapterState.poweredOn;
}
