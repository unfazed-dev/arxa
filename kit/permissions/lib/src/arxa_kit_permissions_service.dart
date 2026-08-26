import 'arxa_kit_permission.dart';
import 'arxa_kit_permission_status.dart';

/// Port for querying and requesting OS permissions.
///
/// This is the seam the app depends on. The production binding
/// (`PermissionHandlerArxaKitPermissionsService`) wraps `permission_handler`; tests
/// and demos use the scriptable fake from `package:arxa_kit_permissions/arxa_kit_testing.dart`.
///
/// The escort contract: when a query/request returns
/// [ArxaKitPermissionStatus.permanentlyDenied] (or [ArxaKitPermissionStatus.restricted]),
/// the UI must stop re-prompting and instead route the user to the system
/// settings screen via [openAppSettings].
abstract interface class ArxaKitPermissionsService {
  /// The current status of [permission] without prompting the user.
  Future<ArxaKitPermissionStatus> status(ArxaKitPermission permission);

  /// Requests [permission], prompting the user if the OS allows it.
  ///
  /// Returns the resulting status. A [ArxaKitPermissionStatus.permanentlyDenied]
  /// result means no prompt was shown and none will be — escort to settings.
  Future<ArxaKitPermissionStatus> request(ArxaKitPermission permission);

  /// Requests several permissions and returns each result keyed by permission.
  ///
  /// The platform may batch these into a single prompt sequence.
  Future<Map<ArxaKitPermission, ArxaKitPermissionStatus>> requestEach(
    List<ArxaKitPermission> permissions,
  );

  /// Whether the OS recommends showing a rationale before the next request.
  ///
  /// Android-only signal (`shouldShowRequestPermissionRationale`); always
  /// `false` on iOS, where the system prompt is shown at most once.
  Future<bool> shouldShowRationale(ArxaKitPermission permission);

  /// Opens the app's page in the system Settings app.
  ///
  /// Returns `true` if the settings screen was opened. This is the recovery
  /// path for [ArxaKitPermissionStatus.permanentlyDenied].
  Future<bool> openAppSettings();
}
