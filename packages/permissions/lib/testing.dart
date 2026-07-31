/// Scriptable test doubles for appbox_kit_permissions.
///
/// Import in tests and demos to drive the permission port without touching the
/// OS:
///
/// ```dart
/// final perms = FakeKitPermissionsService();
/// // Model the settings-escort scenario: the request comes back
/// // permanentlyDenied, so the UI must route to app settings.
/// perms.script(KitPermission.camera, [KitPermissionStatus.permanentlyDenied]);
///
/// final status = await perms.request(KitPermission.camera);
/// if (status.requiresSettingsEscort) {
///   await perms.openAppSettings();
/// }
/// expect(perms.openAppSettingsCallCount, 1);
/// ```
library;

import 'src/kit_permission.dart';
import 'src/kit_permission_status.dart';
import 'src/kit_permissions_service.dart';

export 'src/kit_permission.dart';
export 'src/kit_permission_status.dart';
export 'src/kit_permissions_service.dart';

/// An in-memory [KitPermissionsService] whose responses are fully scripted.
///
/// Behaviour:
/// - [status] returns the current stored status (default [defaultStatus]).
/// - [request] pops the next scripted result for that permission if one was
///   queued via [script]; otherwise it grants (or returns the stored status
///   when that status [KitPermissionStatus.requiresSettingsEscort]). The
///   resulting status is stored so subsequent [status] calls agree.
/// - [openAppSettings] records the call and returns [settingsWillOpen].
///
/// The class records interactions so tests can assert the escort flow:
/// [requestLog], [openAppSettingsCallCount].
class FakeKitPermissionsService implements KitPermissionsService {
  FakeKitPermissionsService({
    Map<KitPermission, KitPermissionStatus>? initial,
    this.defaultStatus = KitPermissionStatus.denied,
    this.settingsWillOpen = true,
    Set<KitPermission>? rationaleFor,
  })  : _statuses = {...?initial},
        _rationaleFor = {...?rationaleFor};

  /// Status returned for a permission that has no stored value.
  final KitPermissionStatus defaultStatus;

  /// Value [openAppSettings] returns.
  final bool settingsWillOpen;

  final Map<KitPermission, KitPermissionStatus> _statuses;
  final Map<KitPermission, List<KitPermissionStatus>> _scripts = {};
  final Set<KitPermission> _rationaleFor;

  /// Every permission passed to [request], in call order.
  final List<KitPermission> requestLog = [];

  /// How many times [openAppSettings] was invoked.
  int openAppSettingsCallCount = 0;

  /// Queues [results] to be returned by successive [request] calls for
  /// [permission]. Overwrites any existing script.
  void script(KitPermission permission, List<KitPermissionStatus> results) {
    _scripts[permission] = [...results];
  }

  /// Directly sets the stored status for [permission] (as if the OS state
  /// changed out from under the app).
  void setStatus(KitPermission permission, KitPermissionStatus status) {
    _statuses[permission] = status;
  }

  /// Makes [shouldShowRationale] return `true` for [permission].
  void enableRationale(KitPermission permission) =>
      _rationaleFor.add(permission);

  @override
  Future<KitPermissionStatus> status(KitPermission permission) async {
    return _statuses[permission] ?? defaultStatus;
  }

  @override
  Future<KitPermissionStatus> request(KitPermission permission) async {
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
        : KitPermissionStatus.granted;
    _statuses[permission] = result;
    return result;
  }

  @override
  Future<Map<KitPermission, KitPermissionStatus>> requestEach(
    List<KitPermission> permissions,
  ) async {
    return {
      for (final permission in permissions) permission: await request(permission),
    };
  }

  @override
  Future<bool> shouldShowRationale(KitPermission permission) async {
    return _rationaleFor.contains(permission);
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return settingsWillOpen;
  }
}
