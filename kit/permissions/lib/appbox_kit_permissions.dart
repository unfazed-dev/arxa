/// appbox_kit_permissions — a plugin-neutral port for OS permissions.
///
/// The app depends on [AppBoxKitPermissionsService] and the [AppBoxKitPermission] /
/// [AppBoxKitPermissionStatus] value types. The production binding
/// ([PermissionHandlerAppBoxKitPermissionsService]) wraps `permission_handler`;
/// scriptable fakes live in `package:appbox_kit_permissions/appbox_kit_testing.dart`.
///
/// This package intentionally depends on no other kit (not `appbox_kit`,
/// `stacked`, or `stacked_services`) — it is a pure port over a native plugin.
library;

export 'src/appbox_kit_permission.dart';
export 'src/appbox_kit_permission_status.dart';
export 'src/appbox_kit_permissions_service.dart';
export 'src/appbox_kit_permission_handler_permissions_service.dart';
