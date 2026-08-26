import 'package:permission_handler/permission_handler.dart' as ph;

import 'arxa_kit_permission.dart';
import 'arxa_kit_permission_status.dart';
import 'arxa_kit_permissions_service.dart';

/// Production [ArxaKitPermissionsService] backed by `permission_handler`.
///
/// Thin adapter: it maps the neutral [ArxaKitPermission] enum to a concrete
/// `permission_handler` [ph.Permission] and projects the plugin's
/// [ph.PermissionStatus] onto the four-state [ArxaKitPermissionStatus]. It holds
/// no state of its own — every call is a live OS query.
class PermissionHandlerArxaKitPermissionsService implements ArxaKitPermissionsService {
  const PermissionHandlerArxaKitPermissionsService();

  @override
  Future<ArxaKitPermissionStatus> status(ArxaKitPermission permission) async {
    final status = await _permissionFor(permission).status;
    return _map(status);
  }

  @override
  Future<ArxaKitPermissionStatus> request(ArxaKitPermission permission) async {
    final status = await _permissionFor(permission).request();
    return _map(status);
  }

  @override
  Future<Map<ArxaKitPermission, ArxaKitPermissionStatus>> requestEach(
    List<ArxaKitPermission> permissions,
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
  Future<bool> shouldShowRationale(ArxaKitPermission permission) {
    // iOS has no rationale concept; the plugin returns false there.
    return _permissionFor(permission).shouldShowRequestRationale;
  }

  @override
  Future<bool> openAppSettings() => ph.openAppSettings();

  /// Maps the neutral kit enum to the plugin permission.
  ph.Permission _permissionFor(ArxaKitPermission permission) {
    switch (permission) {
      case ArxaKitPermission.camera:
        return ph.Permission.camera;
      case ArxaKitPermission.microphone:
        return ph.Permission.microphone;
      case ArxaKitPermission.photos:
        return ph.Permission.photos;
      case ArxaKitPermission.bluetooth:
        return ph.Permission.bluetooth;
      case ArxaKitPermission.location:
        return ph.Permission.location;
      case ArxaKitPermission.notifications:
        return ph.Permission.notification;
    }
  }

  /// Projects the plugin's richer status onto the four actionable states.
  ///
  /// `limited` (partial iOS photo access) and `provisional` (quiet iOS
  /// notifications) both mean the feature has usable access, so they map to
  /// [ArxaKitPermissionStatus.granted].
  ArxaKitPermissionStatus _map(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return ArxaKitPermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return ArxaKitPermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return ArxaKitPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return ArxaKitPermissionStatus.restricted;
    }
  }
}
