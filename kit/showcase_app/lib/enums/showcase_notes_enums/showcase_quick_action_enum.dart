/// A one-tap compose intent carried by the note route's `?quickAction=`
/// query param — [name] IS the wire value ('camera'/'mic'); the route
/// format must not change.
enum ShowcaseQuickAction {
  camera('New Photo'),
  mic('New Voice');

  const ShowcaseQuickAction(this.label);

  /// Label in the folder view's compose FAB menu.
  final String label;

  /// Null-safe route parse — an absent or unknown param means "no quick
  /// action".
  static ShowcaseQuickAction? fromRoute(String? value) {
    for (final action in ShowcaseQuickAction.values) {
      if (action.name == value) return action;
    }
    return null;
  }
}
