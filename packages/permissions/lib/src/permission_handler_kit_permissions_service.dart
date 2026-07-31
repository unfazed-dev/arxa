import 'package:permission_handler/permission_handler.dart' as ph;

import 'kit_permission.dart';
import 'kit_permission_status.dart';
import 'kit_permissions_service.dart';

/// Production [KitPermissionsService] backed by `permission_handler`.
///
/// Thin adapter: it maps the neutral [KitPermission] enum to a concrete
/// `permission_handler` [ph.Permission] and projects the plugin's
/// [ph.PermissionStatus] onto the four-state [KitPermissionStatus]. It holds
/// no state of its own — every call is a live OS query.
class PermissionHandlerKitPermissionsService implements KitPermissionsService {
  const PermissionHandlerKitPermissionsService();

  @override
  Future<KitPermissionStatus> status(KitPermission permission) async {
    final status = await _permissionFor(permission).status;
    return _map(status);
  }

  @override
  Future<KitPermissionStatus> request(KitPermission permission) async {
    final status = await _permissionFor(permission).request();
    return _map(status);
  }

  @override
  Future<Map<KitPermission, KitPermissionStatus>> requestEach(
    List<KitPermission> permissions,
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
  Future<bool> shouldShowRationale(KitPermission permission) {
    // iOS has no rationale concept; the plugin returns false there.
    return _permissionFor(permission).shouldShowRequestRationale;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  /// Maps the neutral kit enum to the plugin permission.
  ph.Permission _permissionFor(KitPermission permission) {
    switch (permission) {
      case KitPermission.camera:
        return ph.Permission.camera;
      case KitPermission.microphone:
        return ph.Permission.microphone;
      case KitPermission.photos:
        return ph.Permission.photos;
      case KitPermission.bluetooth:
        return ph.Permission.bluetooth;
      case KitPermission.location:
        return ph.Permission.location;
      case KitPermission.notifications:
        return ph.Permission.notification;
    }
  }

  /// Projects the plugin's richer status onto the four actionable states.
  ///
  /// `limited` (partial iOS photo access) and `provisional` (quiet iOS
  /// notifications) both mean the feature has usable access, so they map to
  /// [KitPermissionStatus.granted].
  KitPermissionStatus _map(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return KitPermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return KitPermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return KitPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return KitPermissionStatus.restricted;
    }
  }
}
