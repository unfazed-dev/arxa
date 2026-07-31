/// What the current platform lets this kit do with the Bluetooth adapter, so
/// demo UIs can label a control **direct** vs **escorted**.
///
/// Android exposes a system dialog to enable the adapter
/// (`BluetoothAdapter.ACTION_REQUEST_ENABLE`, surfaced by
/// `FlutterBluePlus.turnOn`), so `canControlAdapter` is `true` there. iOS has
/// no such API — the only affordance is deep-linking into Settings, so
/// `canControlAdapter` is `false` and the UI must escort.
class KitBluetoothCapabilities {
  const KitBluetoothCapabilities({
    required this.canControlAdapter,
  });

  /// True where `requestEnable()` can show an OS enable dialog (Android).
  /// `false` on iOS — escort via `openSettings()` instead.
  final bool canControlAdapter;

  /// Android: the adapter can be enabled via a system dialog.
  static const androidDialog = KitBluetoothCapabilities(canControlAdapter: true);

  /// iOS / other: observe + escort only.
  static const escortOnly = KitBluetoothCapabilities(canControlAdapter: false);
}
