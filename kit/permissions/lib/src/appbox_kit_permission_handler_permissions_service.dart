import 'package:permission_handler/permission_handler.dart' as ph;

import 'appbox_kit_permission.dart';
import 'appbox_kit_permission_status.dart';
import 'appbox_kit_permissions_service.dart';

/// Production [AppBoxKitPermissionsService] backed by `permission_handler`.
///
/// Thin adapter: it maps the neutral [AppBoxKitPermission] enum to a concrete
/// `permission_handler` [ph.Permission] and projects the plugin's
/// [ph.PermissionStatus] onto the four-state [AppBoxKitPermissionStatus]. It holds
/// no state of its own — every call is a live OS query.
class PermissionHandlerAppBoxKitPermissionsService implements AppBoxKitPermissionsService {
  const PermissionHandlerAppBoxKitPermissionsService();

  @override
  Future<AppBoxKitPermissionStatus> status(AppBoxKitPermission permission) async {
    final status = await _permissionFor(permission).status;
    return _map(status);
  }

  @override
  Future<AppBoxKitPermissionStatus> request(AppBoxKitPermission permission) async {
    final status = await _permissionFor(permission).request();
    return _map(status);
  }

  @override
  Future<Map<AppBoxKitPermission, AppBoxKitPermissionStatus>> requestEach(
    List<AppBoxKitPermission> permissions,
  ) async {
    final results = await permissions
        .map(_permissionFor)
        .toList()
        .request();
    return {
      for (final permission in permissions)
        permission: _map(results[_permissionFor(permission)]!),
    };
  }

  @override
  Future<bool> shouldShowRationale(AppBoxKitPermission permission) {
    // iOS has no rationale concept; the plugin returns false there.
    return _permissionFor(permission).shouldShowRequestRationale;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  /// Maps the neutral kit enum to the plugin permission.
  ph.Permission _permissionFor(AppBoxKitPermission permission) {
    switch (permission) {
      case AppBoxKitPermission.camera:
        return ph.Permission.camera;
      case AppBoxKitPermission.microphone:
        return ph.Permission.microphone;
      case AppBoxKitPermission.photos:
        return ph.Permission.photos;
      case AppBoxKitPermission.bluetooth:
        return ph.Permission.bluetooth;
      case AppBoxKitPermission.location:
        return ph.Permission.location;
      case AppBoxKitPermission.notifications:
        return ph.Permission.notification;
    }
  }

  /// Projects the plugin's richer status onto the four actionable states.
  ///
  /// `limited` (partial iOS photo access) and `provisional` (quiet iOS
  /// notifications) both mean the feature has usable access, so they map to
  /// [AppBoxKitPermissionStatus.granted].
  AppBoxKitPermissionStatus _map(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return AppBoxKitPermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return AppBoxKitPermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return AppBoxKitPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return AppBoxKitPermissionStatus.restricted;
    }
  }
}
