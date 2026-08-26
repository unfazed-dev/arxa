/// A three-valued answer for an integrity signal that may be affirmatively
/// true, affirmatively false, or genuinely undeterminable on this platform.
///
/// [unknown] is a first-class value, not a default to be ignored: a signal the
/// current platform cannot measure must not be reported as a safe [no].
enum ArxaKitTriState {
  /// The condition holds (e.g. the device *is* rooted).
  yes,

  /// The condition does not hold (e.g. the device is *not* rooted).
  no,

  /// The platform could not determine the condition.
  unknown,
}
