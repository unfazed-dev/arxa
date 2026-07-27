// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i20;
import 'package:stacked/stacked.dart' as _i19;
import 'package:stacked_services/stacked_services.dart' as _i18;

import '../ui/views/app_shell/app_shell_view.dart' as _i2;
import '../ui/views/build/build_approve/build_approve_view.dart' as _i11;
import '../ui/views/build/build_finding/build_finding_view.dart' as _i10;
import '../ui/views/build/build_run/build_run_view.dart' as _i9;
import '../ui/views/chat/chat_home/chat_home_view.dart' as _i14;
import '../ui/views/design/design_approve/design_approve_view.dart' as _i8;
import '../ui/views/design/design_directions/design_directions_view.dart'
    as _i6;
import '../ui/views/design/design_surface/design_surface_view.dart' as _i7;
import '../ui/views/projects/projects_home/projects_home_view.dart' as _i4;
import '../ui/views/projects/projects_new/projects_new_view.dart' as _i5;
import '../ui/views/settings/settings_credentials/settings_credentials_view.dart'
    as _i15;
import '../ui/views/settings/settings_devices/settings_devices_view.dart'
    as _i16;
import '../ui/views/settings/settings_kits/settings_kits_view.dart' as _i17;
import '../ui/views/ship/ship_confirm/ship_confirm_view.dart' as _i13;
import '../ui/views/ship/ship_targets/ship_targets_view.dart' as _i12;
import '../ui/views/showcase_startup/showcase_startup_view.dart' as _i1;
import '../ui/views/showcase_unknown/showcase_unknown_view.dart' as _i3;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i18.StackedService.navigatorKey);

class StackedRouterWeb extends _i19.RootStackRouter {
  StackedRouterWeb({_i20.GlobalKey<_i20.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i19.PageFactory> pagesMap = {
    ShowcaseStartupViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseStartupViewArgs>(
          orElse: () => const ShowcaseStartupViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.ShowcaseStartupView(key: args.key),
        opaque: true,
      );
    },
    AppShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<AppShellViewArgs>(
          orElse: () => const AppShellViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.AppShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseUnknownViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseUnknownViewArgs>(
          orElse: () => const ShowcaseUnknownViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.ShowcaseUnknownView(key: args.key),
        opaque: true,
      );
    },
    ProjectsHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ProjectsHomeViewArgs>(
          orElse: () => const ProjectsHomeViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.ProjectsHomeView(key: args.key),
        opaque: true,
      );
    },
    ProjectsNewViewRoute.name: (routeData) {
      final args = routeData.argsAs<ProjectsNewViewArgs>(
          orElse: () => const ProjectsNewViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ProjectsNewView(key: args.key),
        opaque: true,
      );
    },
    DesignDirectionsViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignDirectionsViewArgs>(
          orElse: () => const DesignDirectionsViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.DesignDirectionsView(key: args.key),
        opaque: true,
      );
    },
    DesignSurfaceViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignSurfaceViewArgs>(
          orElse: () => const DesignSurfaceViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i7.DesignSurfaceView(key: args.key),
        opaque: true,
      );
    },
    DesignApproveViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignApproveViewArgs>(
          orElse: () => const DesignApproveViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i8.DesignApproveView(key: args.key),
        opaque: true,
      );
    },
    BuildRunViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildRunViewArgs>(
          orElse: () => const BuildRunViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i9.BuildRunView(key: args.key),
        opaque: true,
      );
    },
    BuildFindingViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildFindingViewArgs>(
          orElse: () => const BuildFindingViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i10.BuildFindingView(key: args.key),
        opaque: true,
      );
    },
    BuildApproveViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildApproveViewArgs>(
          orElse: () => const BuildApproveViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i11.BuildApproveView(key: args.key),
        opaque: true,
      );
    },
    ShipTargetsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShipTargetsViewArgs>(
          orElse: () => const ShipTargetsViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i12.ShipTargetsView(key: args.key),
        opaque: true,
      );
    },
    ShipConfirmViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShipConfirmViewArgs>(
          orElse: () => const ShipConfirmViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i13.ShipConfirmView(key: args.key),
        opaque: true,
      );
    },
    ChatHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ChatHomeViewArgs>(
          orElse: () => const ChatHomeViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i14.ChatHomeView(key: args.key),
        opaque: true,
      );
    },
    SettingsCredentialsViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsCredentialsViewArgs>(
          orElse: () => const SettingsCredentialsViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i15.SettingsCredentialsView(key: args.key),
        opaque: true,
      );
    },
    SettingsDevicesViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsDevicesViewArgs>(
          orElse: () => const SettingsDevicesViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i16.SettingsDevicesView(key: args.key),
        opaque: true,
      );
    },
    SettingsKitsViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsKitsViewArgs>(
          orElse: () => const SettingsKitsViewArgs());
      return _i19.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i17.SettingsKitsView(key: args.key),
        opaque: true,
      );
    },
  };

  @override
  List<_i19.RouteConfig> get routes => [
        _i19.RouteConfig(
          ShowcaseStartupViewRoute.name,
          path: '/',
        ),
        _i19.RouteConfig(
          AppShellViewRoute.name,
          path: '/',
          children: [
            _i19.RouteConfig(
              '#redirect',
              path: '',
              parent: AppShellViewRoute.name,
              redirectTo: 'projects',
              fullMatch: true,
            ),
            _i19.RouteConfig(
              ProjectsHomeViewRoute.name,
              path: 'projects',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              ProjectsNewViewRoute.name,
              path: 'projects/new',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              DesignDirectionsViewRoute.name,
              path: 'design',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              DesignSurfaceViewRoute.name,
              path: 'design/surface',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              DesignApproveViewRoute.name,
              path: 'design/approve',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              BuildRunViewRoute.name,
              path: 'build',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              BuildFindingViewRoute.name,
              path: 'build/finding',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              BuildApproveViewRoute.name,
              path: 'build/approve',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              ShipTargetsViewRoute.name,
              path: 'ship',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              ShipConfirmViewRoute.name,
              path: 'ship/confirm',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              ChatHomeViewRoute.name,
              path: 'chat',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              SettingsCredentialsViewRoute.name,
              path: 'settings',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              SettingsDevicesViewRoute.name,
              path: 'settings/devices',
              parent: AppShellViewRoute.name,
            ),
            _i19.RouteConfig(
              SettingsKitsViewRoute.name,
              path: 'settings/kits',
              parent: AppShellViewRoute.name,
            ),
          ],
        ),
        _i19.RouteConfig(
          ShowcaseUnknownViewRoute.name,
          path: '/404',
        ),
        _i19.RouteConfig(
          '*#redirect',
          path: '*',
          redirectTo: '/404',
          fullMatch: true,
        ),
      ];
}

/// generated route for
/// [_i1.ShowcaseStartupView]
class ShowcaseStartupViewRoute
    extends _i19.PageRouteInfo<ShowcaseStartupViewArgs> {
  ShowcaseStartupViewRoute({_i20.Key? key})
      : super(
          ShowcaseStartupViewRoute.name,
          path: '/',
          args: ShowcaseStartupViewArgs(key: key),
        );

  static const String name = 'ShowcaseStartupView';
}

class ShowcaseStartupViewArgs {
  const ShowcaseStartupViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ShowcaseStartupViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.AppShellView]
class AppShellViewRoute extends _i19.PageRouteInfo<AppShellViewArgs> {
  AppShellViewRoute({
    _i20.Key? key,
    List<_i19.PageRouteInfo>? children,
  }) : super(
          AppShellViewRoute.name,
          path: '/',
          args: AppShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'AppShellView';
}

class AppShellViewArgs {
  const AppShellViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'AppShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.ShowcaseUnknownView]
class ShowcaseUnknownViewRoute
    extends _i19.PageRouteInfo<ShowcaseUnknownViewArgs> {
  ShowcaseUnknownViewRoute({_i20.Key? key})
      : super(
          ShowcaseUnknownViewRoute.name,
          path: '/404',
          args: ShowcaseUnknownViewArgs(key: key),
        );

  static const String name = 'ShowcaseUnknownView';
}

class ShowcaseUnknownViewArgs {
  const ShowcaseUnknownViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ShowcaseUnknownViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.ProjectsHomeView]
class ProjectsHomeViewRoute extends _i19.PageRouteInfo<ProjectsHomeViewArgs> {
  ProjectsHomeViewRoute({_i20.Key? key})
      : super(
          ProjectsHomeViewRoute.name,
          path: 'projects',
          args: ProjectsHomeViewArgs(key: key),
        );

  static const String name = 'ProjectsHomeView';
}

class ProjectsHomeViewArgs {
  const ProjectsHomeViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ProjectsHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ProjectsNewView]
class ProjectsNewViewRoute extends _i19.PageRouteInfo<ProjectsNewViewArgs> {
  ProjectsNewViewRoute({_i20.Key? key})
      : super(
          ProjectsNewViewRoute.name,
          path: 'projects/new',
          args: ProjectsNewViewArgs(key: key),
        );

  static const String name = 'ProjectsNewView';
}

class ProjectsNewViewArgs {
  const ProjectsNewViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ProjectsNewViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.DesignDirectionsView]
class DesignDirectionsViewRoute
    extends _i19.PageRouteInfo<DesignDirectionsViewArgs> {
  DesignDirectionsViewRoute({_i20.Key? key})
      : super(
          DesignDirectionsViewRoute.name,
          path: 'design',
          args: DesignDirectionsViewArgs(key: key),
        );

  static const String name = 'DesignDirectionsView';
}

class DesignDirectionsViewArgs {
  const DesignDirectionsViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'DesignDirectionsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i7.DesignSurfaceView]
class DesignSurfaceViewRoute extends _i19.PageRouteInfo<DesignSurfaceViewArgs> {
  DesignSurfaceViewRoute({_i20.Key? key})
      : super(
          DesignSurfaceViewRoute.name,
          path: 'design/surface',
          args: DesignSurfaceViewArgs(key: key),
        );

  static const String name = 'DesignSurfaceView';
}

class DesignSurfaceViewArgs {
  const DesignSurfaceViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'DesignSurfaceViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i8.DesignApproveView]
class DesignApproveViewRoute extends _i19.PageRouteInfo<DesignApproveViewArgs> {
  DesignApproveViewRoute({_i20.Key? key})
      : super(
          DesignApproveViewRoute.name,
          path: 'design/approve',
          args: DesignApproveViewArgs(key: key),
        );

  static const String name = 'DesignApproveView';
}

class DesignApproveViewArgs {
  const DesignApproveViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'DesignApproveViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i9.BuildRunView]
class BuildRunViewRoute extends _i19.PageRouteInfo<BuildRunViewArgs> {
  BuildRunViewRoute({_i20.Key? key})
      : super(
          BuildRunViewRoute.name,
          path: 'build',
          args: BuildRunViewArgs(key: key),
        );

  static const String name = 'BuildRunView';
}

class BuildRunViewArgs {
  const BuildRunViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'BuildRunViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i10.BuildFindingView]
class BuildFindingViewRoute extends _i19.PageRouteInfo<BuildFindingViewArgs> {
  BuildFindingViewRoute({_i20.Key? key})
      : super(
          BuildFindingViewRoute.name,
          path: 'build/finding',
          args: BuildFindingViewArgs(key: key),
        );

  static const String name = 'BuildFindingView';
}

class BuildFindingViewArgs {
  const BuildFindingViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'BuildFindingViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i11.BuildApproveView]
class BuildApproveViewRoute extends _i19.PageRouteInfo<BuildApproveViewArgs> {
  BuildApproveViewRoute({_i20.Key? key})
      : super(
          BuildApproveViewRoute.name,
          path: 'build/approve',
          args: BuildApproveViewArgs(key: key),
        );

  static const String name = 'BuildApproveView';
}

class BuildApproveViewArgs {
  const BuildApproveViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'BuildApproveViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i12.ShipTargetsView]
class ShipTargetsViewRoute extends _i19.PageRouteInfo<ShipTargetsViewArgs> {
  ShipTargetsViewRoute({_i20.Key? key})
      : super(
          ShipTargetsViewRoute.name,
          path: 'ship',
          args: ShipTargetsViewArgs(key: key),
        );

  static const String name = 'ShipTargetsView';
}

class ShipTargetsViewArgs {
  const ShipTargetsViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ShipTargetsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i13.ShipConfirmView]
class ShipConfirmViewRoute extends _i19.PageRouteInfo<ShipConfirmViewArgs> {
  ShipConfirmViewRoute({_i20.Key? key})
      : super(
          ShipConfirmViewRoute.name,
          path: 'ship/confirm',
          args: ShipConfirmViewArgs(key: key),
        );

  static const String name = 'ShipConfirmView';
}

class ShipConfirmViewArgs {
  const ShipConfirmViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ShipConfirmViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i14.ChatHomeView]
class ChatHomeViewRoute extends _i19.PageRouteInfo<ChatHomeViewArgs> {
  ChatHomeViewRoute({_i20.Key? key})
      : super(
          ChatHomeViewRoute.name,
          path: 'chat',
          args: ChatHomeViewArgs(key: key),
        );

  static const String name = 'ChatHomeView';
}

class ChatHomeViewArgs {
  const ChatHomeViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'ChatHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i15.SettingsCredentialsView]
class SettingsCredentialsViewRoute
    extends _i19.PageRouteInfo<SettingsCredentialsViewArgs> {
  SettingsCredentialsViewRoute({_i20.Key? key})
      : super(
          SettingsCredentialsViewRoute.name,
          path: 'settings',
          args: SettingsCredentialsViewArgs(key: key),
        );

  static const String name = 'SettingsCredentialsView';
}

class SettingsCredentialsViewArgs {
  const SettingsCredentialsViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'SettingsCredentialsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i16.SettingsDevicesView]
class SettingsDevicesViewRoute
    extends _i19.PageRouteInfo<SettingsDevicesViewArgs> {
  SettingsDevicesViewRoute({_i20.Key? key})
      : super(
          SettingsDevicesViewRoute.name,
          path: 'settings/devices',
          args: SettingsDevicesViewArgs(key: key),
        );

  static const String name = 'SettingsDevicesView';
}

class SettingsDevicesViewArgs {
  const SettingsDevicesViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'SettingsDevicesViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i17.SettingsKitsView]
class SettingsKitsViewRoute extends _i19.PageRouteInfo<SettingsKitsViewArgs> {
  SettingsKitsViewRoute({_i20.Key? key})
      : super(
          SettingsKitsViewRoute.name,
          path: 'settings/kits',
          args: SettingsKitsViewArgs(key: key),
        );

  static const String name = 'SettingsKitsView';
}

class SettingsKitsViewArgs {
  const SettingsKitsViewArgs({this.key});

  final _i20.Key? key;

  @override
  String toString() {
    return 'SettingsKitsViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i18.RouterService {
  Future<dynamic> navigateToShowcaseStartupView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToAppShellView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      AppShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseUnknownView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedProjectsHomeViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ProjectsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedProjectsNewViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ProjectsNewViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignDirectionsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignDirectionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignSurfaceViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignSurfaceViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignApproveViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildRunViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildRunViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildFindingViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildFindingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildApproveViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedShipTargetsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShipTargetsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedShipConfirmViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShipConfirmViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedChatHomeViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ChatHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsCredentialsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsCredentialsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsDevicesViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsDevicesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsKitsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsKitsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseStartupView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithAppShellView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      AppShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseUnknownView({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedProjectsHomeViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ProjectsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedProjectsNewViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ProjectsNewViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignDirectionsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignDirectionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignSurfaceViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignSurfaceViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignApproveViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildRunViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildRunViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildFindingViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildFindingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildApproveViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedShipTargetsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShipTargetsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedShipConfirmViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShipConfirmViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedChatHomeViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ChatHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsCredentialsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsCredentialsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsDevicesViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsDevicesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsKitsViewInAppShellViewRouter({
    _i20.Key? key,
    void Function(_i19.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsKitsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
