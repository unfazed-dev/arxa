/// The app's four tabs, in tab order — the shell's routes, the tab bar, and
/// chrome shortcuts all index into [ShowcaseTab.values] (`.index` IS the
/// TabsRouter index).
enum ShowcaseTab {
  home('Home', 'home'),
  search('Search', 'search'),
  profile('Profile', 'profile'),
  notes('Notes', 'notes');

  const ShowcaseTab(this.label, this.path);

  /// Tab-bar label.
  final String label;

  /// Shell route path segment — must match the shell's children in
  /// `app.dart` (the single contract between shell and routes).
  final String path;
}
