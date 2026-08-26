/// The three states of the app-lock machine.
///
/// The attempt counters and lockout/cooldown windows are *observable fields* on
/// [ArxaKitAppLockController], not extra states — the machine itself is exactly
/// these three values.
enum ArxaKitAppLockState {
  /// The app is open; content is accessible.
  unlocked,

  /// The app is sealed; the user must authenticate to proceed.
  locked,

  /// An unlock attempt is in flight (awaiting biometric prompt / PIN check).
  unlocking,
}
