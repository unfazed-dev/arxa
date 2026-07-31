/// appbox_kit_permissions — a plugin-neutral port for OS permissions.
///
/// The app depends on [KitPermissionsService] and the [KitPermission] /
/// [KitPermissionStatus] value types. The production binding
/// ([PermissionHandlerKitPermissionsService]) wraps `permission_handler`;
/// scriptable fakes live in `package:appbox_kit_permissions/testing.dart`.
///
/// This package intentionally depends on no other kit (not `appbox_kit`,
/// `stacked`, or `stacked_services`) — it is a pure port over a native plugin.
library;

export 'src/kit_permission.dart';
export 'src/kit_permission_status.dart';
export 'src/kit_permissions_service.dart';
export 'src/permission_handler_kit_permissions_service.dart';
