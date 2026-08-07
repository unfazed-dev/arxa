/// The profile demo's navigation-rail destinations, in rail order.
enum ShowcaseProfileRail {
  account('Account'),
  privacy('Privacy'),
  alerts('Alerts');

  const ShowcaseProfileRail(this.label);

  /// Destination label.
  final String label;
}
