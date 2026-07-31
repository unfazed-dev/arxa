/// appbox_kit_wifi — a plugin-neutral port for observing Wi-Fi state and
/// escorting the user to Wi-Fi settings.
///
/// The implemented priority is adapter-state **observation** (a live OS
/// connectivity stream) plus the **escort** flow; direct adapter control and
/// programmatic join are deliberate stubs — no mobile OS exposes them.
///
/// This package depends on no other kit (not `appbox_kit`, `stacked`, or
/// `stacked_services`) — pure port over native plugins.
library;

export 'src/kit_wifi_capabilities.dart';
export 'src/kit_wifi_network.dart';
export 'src/kit_wifi_service.dart';
export 'src/kit_wifi_state.dart';
export 'src/connectivity_kit_wifi_service.dart';
