import 'kit_permission.dart';
import 'kit_permission_status.dart';

/// Port for querying and requesting OS permissions.
///
/// This is the seam the app depends on. The production binding
/// (`PermissionHandlerKitPermissionsService`) wraps `permission_handler`; tests
/// and demos use the scriptable fake from `package:appbox_kit_permissions/testing.dart`.
///
/// The escort contract: when a query/request returns
/// [KitPermissionStatus.permanentlyDenied] (or [KitPermissionStatus.restricted]),
/// the UI must stop re-prompting and instead route the user to the system
/// settings screen via [openAppSettings].
abstract interface class KitPermissionsService {
  /// The current status of [permission] without prompting the user.
  Future<KitPermissionStatus> status(KitPermission permission);

  /// Requests [permission], prompting the user if the OS allows it.
  ///
  /// Returns the resulting status. A [KitPermissionStatus.permanentlyDenied]
  /// result means no prompt was shown and none will be — escort to settings.
  Future<KitPermissionStatus> request(KitPermission permission);

  /// Requests several permissions and returns each result keyed by permission.
  ///
  /// The platform may batch these into a single prompt sequence.
  Future<Map<KitPermission, KitPermissionStatus>> requestEach(
    List<KitPermission> permissions,
  );

  /// Whether the OS recommends showing a rationale before the next request.
  ///
  /// Android-only signal (`shouldShowRequestPermissionRationale`); always
  /// `false` on iOS, where the system prompt is shown at most once.
  Future<bool> shouldShowRationale(KitPermission permission);

  /// Opens the app's page in the system Settings app.
  ///
  /// Returns `true` if the settings screen was opened. This is the recovery
  /// path for [KitPermissionStatus.permanentlyDenied].
  Future<bool> openAppSettings();
}
