/// The typed outcome of a permission query or request.
///
/// This is a lossy-but-actionable projection of the platform status: the four
/// states a UI actually branches on. In particular iOS "limited" (partial
/// photo access) and "provisional" (quiet notifications) both collapse to
/// [granted] — the app has usable access — while the caller can still inspect
/// the platform directly if it needs the finer grain.
enum ArxaKitPermissionStatus {
  /// The permission is granted; the feature may proceed.
  granted,

  /// Denied this time, but the OS will still show the prompt on the next
  /// request. On Android this is the pre-rationale state.
  denied,

  /// Denied and the OS will no longer show the prompt. The only recovery is
  /// to escort the user into the app settings screen (see
  /// `ArxaKitPermissionsService.openAppSettings`).
  permanentlyDenied,

  /// Blocked by the platform outside the user's control (e.g. parental
  /// controls / MDM). Not recoverable from within the app.
  restricted;

  /// True when the feature guarded by this permission may run.
  bool get isUsable => this == ArxaKitPermissionStatus.granted;

  /// True when the only path forward is the OS settings screen.
  bool get requiresSettingsEscort =>
      this == ArxaKitPermissionStatus.permanentlyDenied ||
      this == ArxaKitPermissionStatus.restricted;
}
