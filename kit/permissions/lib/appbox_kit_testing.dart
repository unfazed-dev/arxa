/// Scriptable test doubles for appbox_kit_permissions.
///
/// Import in tests and demos to drive the permission port without touching the
/// OS:
///
/// ```dart
/// final perms = FakeAppBoxKitPermissionsService();
/// // Model the settings-escort scenario: the request comes back
/// // permanentlyDenied, so the UI must route to app settings.
/// perms.script(AppBoxKitPermission.camera, [AppBoxKitPermissionStatus.permanentlyDenied]);
///
/// final status = await perms.request(AppBoxKitPermission.camera);
/// if (status.requiresSettingsEscort) {
///   await perms.openAppSettings();
/// }
/// expect(perms.openAppSettingsCallCount, 1);
/// ```
library;

import 'src/appbox_kit_permission.dart';
import 'src/appbox_kit_permission_status.dart';
import 'src/appbox_kit_permissions_service.dart';

export 'src/appbox_kit_permission.dart';
export 'src/appbox_kit_permission_status.dart';
export 'src/appbox_kit_permissions_service.dart';

/// An in-memory [AppBoxKitPermissionsService] whose responses are fully scripted.
///
/// Behaviour:
/// - [status] returns the current stored status (default [defaultStatus]).
/// - [request] pops the next scripted result for that permission if one was
///   queued via [script]; otherwise it grants (or returns the stored status
///   when that status [AppBoxKitPermissionStatus.requiresSettingsEscort]). The
///   resulting status is stored so subsequent [status] calls agree.
/// - [openAppSettings] records the call and returns [settingsWillOpen].
///
/// The class records interactions so tests can assert the escort flow:
/// [requestLog], [openAppSettingsCallCount].
class FakeAppBoxKitPermissionsService implements AppBoxKitPermissionsService {
  FakeAppBoxKitPermissionsService({
    Map<AppBoxKitPermission, AppBoxKitPermissionStatus>? initial,
    this.defaultStatus = AppBoxKitPermissionStatus.denied,
    this.settingsWillOpen = true,
    Set<AppBoxKitPermission>? rationaleFor,
  })  : _statuses = {...?initial},
        _rationaleFor = {...?rationaleFor};

  /// Status returned for a permission that has no stored value.
  final AppBoxKitPermissionStatus defaultStatus;

  /// Value [openAppSettings] returns.
  final bool settingsWillOpen;

  final Map<AppBoxKitPermission, AppBoxKitPermissionStatus> _statuses;
  final Map<AppBoxKitPermission, List<AppBoxKitPermissionStatus>> _scripts = {};
  final Set<AppBoxKitPermission> _rationaleFor;

  /// Every permission passed to [request], in call order.
  final List<AppBoxKitPermission> requestLog = [];

  /// How many times [openAppSettings] was invoked.
  int openAppSettingsCallCount = 0;

  /// Queues [results] to be returned by successive [request] calls for
  /// [permission]. Overwrites any existing script.
  void script(AppBoxKitPermission permission, List<AppBoxKitPermissionStatus> results) {
    _scripts[permission] = [...results];
  }

  /// Directly sets the stored status for [permission] (as if the OS state
  /// changed out from under the app).
  void setStatus(AppBoxKitPermission permission, AppBoxKitPermissionStatus status) {
    _statuses[permission] = status;
  }

  /// Makes [shouldShowRationale] return `true` for [permission].
  void enableRationale(AppBoxKitPermission permission) =>
      _rationaleFor.add(permission);

  @override
  Future<AppBoxKitPermissionStatus> status(AppBoxKitPermission permission) async {
    return _statuses[permission] ?? defaultStatus;
  }

  @override
  Future<AppBoxKitPermissionStatus> request(AppBoxKitPermission permission) async {
    requestLog.add(permission);

    final current = _statuses[permission] ?? defaultStatus;
    // Permanently-denied / restricted permissions never re-prompt — the OS
    // returns the same terminal state until the user visits settings.
    if (current.requiresSettingsEscort && !_scripts.containsKey(permission)) {
      return current;
    }

    final script = _scripts[permission];
    final result = (script != null && script.isNotEmpty)
        ? script.removeAt(0)
        : AppBoxKitPermissionStatus.granted;
    _statuses[permission] = result;
    return result;
  }

  @override
  Future<Map<AppBoxKitPermission, AppBoxKitPermissionStatus>> requestEach(
    List<AppBoxKitPermission> permissions,
  ) async {
    return {
      for (final permission in permissions) permission: await request(permission),
    };
  }

  @override
  Future<bool> shouldShowRationale(AppBoxKitPermission permission) async {
    return _rationaleFor.contains(permission);
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return settingsWillOpen;
  }
}
