/// arxa_kit_permissions — a plugin-neutral port for OS permissions.
///
/// The app depends on [ArxaKitPermissionsService] and the [ArxaKitPermission] /
/// [ArxaKitPermissionStatus] value types. The production binding
/// ([PermissionHandlerArxaKitPermissionsService]) wraps `permission_handler`;
/// scriptable fakes live in `package:arxa_kit_permissions/arxa_kit_testing.dart`.
///
/// This package intentionally depends on no other kit (not `arxa_kit`,
/// `stacked`, or `stacked_services`) — it is a pure port over a native plugin.
library;

export 'src/arxa_kit_permission.dart';
export 'src/arxa_kit_permission_status.dart';
export 'src/arxa_kit_permissions_service.dart';
export 'src/arxa_kit_permission_handler_permissions_service.dart';
