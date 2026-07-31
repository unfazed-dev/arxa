/// appbox_kit_bluetooth — a plugin-neutral port over `flutter_blue_plus`.
///
/// The implemented priority is adapter-state **observation** (a live OS
/// stream) plus a **capability gate** and the enable/escort flow. Scanning and
/// GATT (connect/read/write/notify) are full stub ports — final signatures,
/// `UnimplementedError` bodies — for phase 2.
///
/// This package depends on no other kit (not `appbox_kit`, `stacked`, or
/// `stacked_services`) — pure port over a native plugin.
library;

export 'src/kit_bluetooth_adapter_state.dart';
export 'src/kit_bluetooth_capabilities.dart';
export 'src/kit_bluetooth_service.dart';
export 'src/flutter_blue_plus_kit_bluetooth_service.dart';

// Stub ports (phase 2)
export 'src/kit_bluetooth_device.dart';
export 'src/kit_bluetooth_scanner.dart';
export 'src/kit_bluetooth_gatt.dart';
