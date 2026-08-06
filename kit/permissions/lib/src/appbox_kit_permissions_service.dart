import 'appbox_kit_permission.dart';
import 'appbox_kit_permission_status.dart';

/// Port for querying and requesting OS permissions.
///
/// This is the seam the app depends on. The production binding
/// (`PermissionHandlerAppBoxKitPermissionsService`) wraps `permission_handler`; tests
/// and demos use the scriptable fake from `package:appbox_kit_permissions/appbox_kit_testing.dart`.
///
/// The escort contract: when a query/request returns
/// [AppBoxKitPermissionStatus.permanentlyDenied] (or [AppBoxKitPermissionStatus.restricted]),
/// the UI must stop re-prompting and instead route the user to the system
/// settings screen via [openAppSettings].
abstract interface class AppBoxKitPermissionsService {
  /// The current status of [permission] without prompting the user.
  Future<AppBoxKitPermissionStatus> status(AppBoxKitPermission permission);

  /// Requests [permission], prompting the user if the OS allows it.
  ///
  /// Returns the resulting status. A [AppBoxKitPermissionStatus.permanentlyDenied]
  /// result means no prompt was shown and none will be — escort to settings.
  Future<AppBoxKitPermissionStatus> request(AppBoxKitPermission permission);

  /// Requests several permissions and returns each result keyed by permission.
  ///
  /// The platform may batch these into a single prompt sequence.
  Future<Map<AppBoxKitPermission, AppBoxKitPermissionStatus>> requestEach(
    List<AppBoxKitPermission> permissions,
  );

  /// Whether the OS recommends showing a rationale before the next request.
  ///
  /// Android-only signal (`shouldShowRequestPermissionRationale`); always
  /// `false` on iOS, where the system prompt is shown at most once.
  Future<bool> shouldShowRationale(AppBoxKitPermission permission);

  /// Opens the app's page in the system Settings app.
  ///
  /// Returns `true` if the settings screen was opened. This is the recovery
  /// path for [AppBoxKitPermissionStatus.permanentlyDenied].
  Future<bool> openAppSettings();
}
