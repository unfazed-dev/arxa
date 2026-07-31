/// The three states of the app-lock machine.
///
/// The attempt counters and lockout/cooldown windows are *observable fields* on
/// [KitAppLockController], not extra states — the machine itself is exactly
/// these three values.
enum KitAppLockState {
  /// The app is open; content is accessible.
  unlocked,

  /// The app is sealed; the user must authenticate to proceed.
  locked,

  /// An unlock attempt is in flight (awaiting biometric prompt / PIN check).
  unlocking,
}
