/// Which credential flow the auth screen shows. Owner-held, mirrors
/// `AppBoxKitNativeSegmentedControl`'s index convention (see the view).
enum ShowcaseNotesAuthMode {
  password('Password'),
  otp('OTP');

  const ShowcaseNotesAuthMode(this.label);

  /// Segment label on the mode toggle.
  final String label;
}
