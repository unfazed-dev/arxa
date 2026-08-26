/// The set of OS permissions this kit can query and request.
///
/// Deliberately small and platform-neutral: each value maps to one concrete
/// backing permission on iOS and Android. Consumers switch on this enum in
/// UI without importing `permission_handler` (or any plugin) directly.
enum ArxaKitPermission {
  /// Camera capture (photo/video).
  camera,

  /// Microphone / audio capture.
  microphone,

  /// Photo library / media gallery read access.
  photos,

  /// Bluetooth usage (scan/connect). On Android 12+ this is the runtime
  /// `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` family; on iOS the CoreBluetooth
  /// usage prompt.
  bluetooth,

  /// Location (when-in-use granularity).
  location,

  /// User-facing notifications.
  notifications,
}
