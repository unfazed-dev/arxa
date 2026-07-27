import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/app/app.router.dart';

/// The six sections (brief §4 tabs). `defaultRoute` is a constructor tear-off
/// (const) returning the section's entry [PageRouteInfo] — the generated route
/// classes are not const-constructible, so the enum holds the builder, not an
/// instance.
enum AppSection {
  projects(Icons.folder_outlined, 'Projects', ProjectsHomeViewRoute.new),
  design(Icons.palette_outlined, 'Design', DesignDirectionsViewRoute.new),
  build(Icons.build_outlined, 'Build', BuildRunViewRoute.new),
  ship(Icons.rocket_launch_outlined, 'Ship', ShipTargetsViewRoute.new),
  chat(Icons.chat_bubble_outline, 'Chat', ChatHomeViewRoute.new),
  settings(Icons.settings_outlined, 'Settings', SettingsCredentialsViewRoute.new);

  final IconData icon;
  final String label;
  final PageRouteInfo Function() defaultRoute;
  const AppSection(this.icon, this.label, this.defaultRoute);
}

/// Reactive on the stacked router (a ChangeNotifier) so the sidebar highlight
/// tracks the active section as the nested router swaps surfaces.
class AppShellViewModel extends BaseViewModel {
  AppShellViewModel() {
    _router.addListener(_onChanged);
  }

  final _router = locator<RouterService>().router;

  void _onChanged() => notifyListeners();

  AppSection get section {
    final name = _router.current.name.toLowerCase();
    for (final s in AppSection.values) {
      if (name.startsWith(s.name)) return s;
    }
    return AppSection.projects;
  }

  void goTo(AppSection s) {
    locator<RouterService>().navigateTo(s.defaultRoute());
  }

  @override
  void dispose() {
    _router.removeListener(_onChanged);
    super.dispose();
  }
}
