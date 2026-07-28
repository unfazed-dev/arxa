// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/foundation.dart' as _i22;
import 'package:flutter/material.dart' as _i21;
import 'package:stacked/stacked.dart' as _i20;
import 'package:stacked_services/stacked_services.dart' as _i19;

import '../ui/views/app_shell/app_shell_view.dart' as _i2;
import '../ui/views/build/build_approve/build_approve_view.dart' as _i12;
import '../ui/views/build/build_finding/build_finding_view.dart' as _i11;
import '../ui/views/build/build_run/build_run_view.dart' as _i10;
import '../ui/views/chat/chat_home/chat_home_view.dart' as _i15;
import '../ui/views/design/design_approve/design_approve_view.dart' as _i9;
import '../ui/views/design/design_directions/design_directions_view.dart'
    as _i7;
import '../ui/views/design/design_surface/design_surface_view.dart' as _i8;
import '../ui/views/intake/intake_wizard/intake_wizard_view.dart' as _i6;
import '../ui/views/projects/projects_home/projects_home_view.dart' as _i4;
import '../ui/views/projects/projects_new/projects_new_view.dart' as _i5;
import '../ui/views/settings/settings_credentials/settings_credentials_view.dart'
    as _i16;
import '../ui/views/settings/settings_devices/settings_devices_view.dart'
    as _i17;
import '../ui/views/settings/settings_kits/settings_kits_view.dart' as _i18;
import '../ui/views/ship/ship_confirm/ship_confirm_view.dart' as _i14;
import '../ui/views/ship/ship_targets/ship_targets_view.dart' as _i13;
import '../ui/views/startup/startup_view.dart' as _i1;
import '../ui/views/unknown/unknown_view.dart' as _i3;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i19.StackedService.navigatorKey);

class StackedRouterWeb extends _i20.RootStackRouter {
  StackedRouterWeb({_i21.GlobalKey<_i21.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i20.PageFactory> pagesMap = {
    StartupViewRoute.name: (routeData) {
      final args = routeData.argsAs<StartupViewArgs>(
          orElse: () => const StartupViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.StartupView(key: args.key),
        opaque: true,
      );
    },
    AppShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<AppShellViewArgs>(
          orElse: () => const AppShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.AppShellView(key: args.key),
        opaque: true,
      );
    },
    UnknownViewRoute.name: (routeData) {
      final args = routeData.argsAs<UnknownViewArgs>(
          orElse: () => const UnknownViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.UnknownView(key: args.key),
        opaque: true,
      );
    },
    ProjectsHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ProjectsHomeViewArgs>(
          orElse: () => const ProjectsHomeViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.ProjectsHomeView(key: args.key),
        opaque: true,
      );
    },
    ProjectsNewViewRoute.name: (routeData) {
      final args = routeData.argsAs<ProjectsNewViewArgs>(
          orElse: () => const ProjectsNewViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ProjectsNewView(key: args.key),
        opaque: true,
      );
    },
    IntakeWizardViewRoute.name: (routeData) {
      final args = routeData.argsAs<IntakeWizardViewArgs>(
          orElse: () => const IntakeWizardViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.IntakeWizardView(key: args.key),
        opaque: true,
      );
    },
    DesignDirectionsViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignDirectionsViewArgs>(
          orElse: () => const DesignDirectionsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i7.DesignDirectionsView(key: args.key),
        opaque: true,
      );
    },
    DesignSurfaceViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignSurfaceViewArgs>(
          orElse: () => const DesignSurfaceViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i8.DesignSurfaceView(key: args.key),
        opaque: true,
      );
    },
    DesignApproveViewRoute.name: (routeData) {
      final args = routeData.argsAs<DesignApproveViewArgs>(
          orElse: () => const DesignApproveViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i9.DesignApproveView(key: args.key),
        opaque: true,
      );
    },
    BuildRunViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildRunViewArgs>(
          orElse: () => const BuildRunViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i10.BuildRunView(key: args.key),
        opaque: true,
      );
    },
    BuildFindingViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildFindingViewArgs>(
          orElse: () => const BuildFindingViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i11.BuildFindingView(key: args.key),
        opaque: true,
      );
    },
    BuildApproveViewRoute.name: (routeData) {
      final args = routeData.argsAs<BuildApproveViewArgs>(
          orElse: () => const BuildApproveViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i12.BuildApproveView(key: args.key),
        opaque: true,
      );
    },
    ShipTargetsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShipTargetsViewArgs>(
          orElse: () => const ShipTargetsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i13.ShipTargetsView(key: args.key),
        opaque: true,
      );
    },
    ShipConfirmViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShipConfirmViewArgs>(
          orElse: () => const ShipConfirmViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i14.ShipConfirmView(key: args.key),
        opaque: true,
      );
    },
    ChatHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ChatHomeViewArgs>(
          orElse: () => const ChatHomeViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i15.ChatHomeView(key: args.key),
        opaque: true,
      );
    },
    SettingsCredentialsViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsCredentialsViewArgs>(
          orElse: () => const SettingsCredentialsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i16.SettingsCredentialsView(key: args.key),
        opaque: true,
      );
    },
    SettingsDevicesViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsDevicesViewArgs>(
          orElse: () => const SettingsDevicesViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i17.SettingsDevicesView(key: args.key),
        opaque: true,
      );
    },
    SettingsKitsViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsKitsViewArgs>(
          orElse: () => const SettingsKitsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i18.SettingsKitsView(key: args.key),
        opaque: true,
      );
    },
  };

  @override
  List<_i20.RouteConfig> get routes => [
        _i20.RouteConfig(
          StartupViewRoute.name,
          path: '/',
        ),
        _i20.RouteConfig(
          AppShellViewRoute.name,
          path: '/',
          children: [
            _i20.RouteConfig(
              '#redirect',
              path: '',
              parent: AppShellViewRoute.name,
              redirectTo: 'projects',
              fullMatch: true,
            ),
            _i20.RouteConfig(
              ProjectsHomeViewRoute.name,
              path: 'projects',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              ProjectsNewViewRoute.name,
              path: 'projects/new',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              IntakeWizardViewRoute.name,
              path: 'intake/wizard',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              DesignDirectionsViewRoute.name,
              path: 'design',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              DesignSurfaceViewRoute.name,
              path: 'design/surface',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              DesignApproveViewRoute.name,
              path: 'design/approve',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              BuildRunViewRoute.name,
              path: 'build',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              BuildFindingViewRoute.name,
              path: 'build/finding',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              BuildApproveViewRoute.name,
              path: 'build/approve',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              ShipTargetsViewRoute.name,
              path: 'ship',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              ShipConfirmViewRoute.name,
              path: 'ship/confirm',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              ChatHomeViewRoute.name,
              path: 'chat',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              SettingsCredentialsViewRoute.name,
              path: 'settings',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              SettingsDevicesViewRoute.name,
              path: 'settings/devices',
              parent: AppShellViewRoute.name,
            ),
            _i20.RouteConfig(
              SettingsKitsViewRoute.name,
              path: 'settings/kits',
              parent: AppShellViewRoute.name,
            ),
          ],
        ),
        _i20.RouteConfig(
          UnknownViewRoute.name,
          path: '/404',
        ),
        _i20.RouteConfig(
          '*#redirect',
          path: '*',
          redirectTo: '/404',
          fullMatch: true,
        ),
      ];
}

/// generated route for
/// [_i1.StartupView]
class StartupViewRoute extends _i20.PageRouteInfo<StartupViewArgs> {
  StartupViewRoute({_i22.Key? key})
      : super(
          StartupViewRoute.name,
          path: '/',
          args: StartupViewArgs(key: key),
        );

  static const String name = 'StartupView';
}

class StartupViewArgs {
  const StartupViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'StartupViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.AppShellView]
class AppShellViewRoute extends _i20.PageRouteInfo<AppShellViewArgs> {
  AppShellViewRoute({
    _i22.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  final _i22.Key? key;

  @override
  String toString() {
    return 'AppShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.UnknownView]
class UnknownViewRoute extends _i20.PageRouteInfo<UnknownViewArgs> {
  UnknownViewRoute({_i22.Key? key})
      : super(
          UnknownViewRoute.name,
          path: '/404',
          args: UnknownViewArgs(key: key),
        );

  static const String name = 'UnknownView';
}

class UnknownViewArgs {
  const UnknownViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'UnknownViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.ProjectsHomeView]
class ProjectsHomeViewRoute extends _i20.PageRouteInfo<ProjectsHomeViewArgs> {
  ProjectsHomeViewRoute({_i22.Key? key})
      : super(
          ProjectsHomeViewRoute.name,
          path: 'projects',
          args: ProjectsHomeViewArgs(key: key),
        );

  static const String name = 'ProjectsHomeView';
}

class ProjectsHomeViewArgs {
  const ProjectsHomeViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'ProjectsHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ProjectsNewView]
class ProjectsNewViewRoute extends _i20.PageRouteInfo<ProjectsNewViewArgs> {
  ProjectsNewViewRoute({_i22.Key? key})
      : super(
          ProjectsNewViewRoute.name,
          path: 'projects/new',
          args: ProjectsNewViewArgs(key: key),
        );

  static const String name = 'ProjectsNewView';
}

class ProjectsNewViewArgs {
  const ProjectsNewViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'ProjectsNewViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.IntakeWizardView]
class IntakeWizardViewRoute extends _i20.PageRouteInfo<IntakeWizardViewArgs> {
  IntakeWizardViewRoute({_i22.Key? key})
      : super(
          IntakeWizardViewRoute.name,
          path: 'intake/wizard',
          args: IntakeWizardViewArgs(key: key),
        );

  static const String name = 'IntakeWizardView';
}

class IntakeWizardViewArgs {
  const IntakeWizardViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'IntakeWizardViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i7.DesignDirectionsView]
class DesignDirectionsViewRoute
    extends _i20.PageRouteInfo<DesignDirectionsViewArgs> {
  DesignDirectionsViewRoute({_i22.Key? key})
      : super(
          DesignDirectionsViewRoute.name,
          path: 'design',
          args: DesignDirectionsViewArgs(key: key),
        );

  static const String name = 'DesignDirectionsView';
}

class DesignDirectionsViewArgs {
  const DesignDirectionsViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'DesignDirectionsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i8.DesignSurfaceView]
class DesignSurfaceViewRoute extends _i20.PageRouteInfo<DesignSurfaceViewArgs> {
  DesignSurfaceViewRoute({_i22.Key? key})
      : super(
          DesignSurfaceViewRoute.name,
          path: 'design/surface',
          args: DesignSurfaceViewArgs(key: key),
        );

  static const String name = 'DesignSurfaceView';
}

class DesignSurfaceViewArgs {
  const DesignSurfaceViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'DesignSurfaceViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i9.DesignApproveView]
class DesignApproveViewRoute extends _i20.PageRouteInfo<DesignApproveViewArgs> {
  DesignApproveViewRoute({_i22.Key? key})
      : super(
          DesignApproveViewRoute.name,
          path: 'design/approve',
          args: DesignApproveViewArgs(key: key),
        );

  static const String name = 'DesignApproveView';
}

class DesignApproveViewArgs {
  const DesignApproveViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'DesignApproveViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i10.BuildRunView]
class BuildRunViewRoute extends _i20.PageRouteInfo<BuildRunViewArgs> {
  BuildRunViewRoute({_i22.Key? key})
      : super(
          BuildRunViewRoute.name,
          path: 'build',
          args: BuildRunViewArgs(key: key),
        );

  static const String name = 'BuildRunView';
}

class BuildRunViewArgs {
  const BuildRunViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'BuildRunViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i11.BuildFindingView]
class BuildFindingViewRoute extends _i20.PageRouteInfo<BuildFindingViewArgs> {
  BuildFindingViewRoute({_i22.Key? key})
      : super(
          BuildFindingViewRoute.name,
          path: 'build/finding',
          args: BuildFindingViewArgs(key: key),
        );

  static const String name = 'BuildFindingView';
}

class BuildFindingViewArgs {
  const BuildFindingViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'BuildFindingViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i12.BuildApproveView]
class BuildApproveViewRoute extends _i20.PageRouteInfo<BuildApproveViewArgs> {
  BuildApproveViewRoute({_i22.Key? key})
      : super(
          BuildApproveViewRoute.name,
          path: 'build/approve',
          args: BuildApproveViewArgs(key: key),
        );

  static const String name = 'BuildApproveView';
}

class BuildApproveViewArgs {
  const BuildApproveViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'BuildApproveViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i13.ShipTargetsView]
class ShipTargetsViewRoute extends _i20.PageRouteInfo<ShipTargetsViewArgs> {
  ShipTargetsViewRoute({_i22.Key? key})
      : super(
          ShipTargetsViewRoute.name,
          path: 'ship',
          args: ShipTargetsViewArgs(key: key),
        );

  static const String name = 'ShipTargetsView';
}

class ShipTargetsViewArgs {
  const ShipTargetsViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'ShipTargetsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i14.ShipConfirmView]
class ShipConfirmViewRoute extends _i20.PageRouteInfo<ShipConfirmViewArgs> {
  ShipConfirmViewRoute({_i22.Key? key})
      : super(
          ShipConfirmViewRoute.name,
          path: 'ship/confirm',
          args: ShipConfirmViewArgs(key: key),
        );

  static const String name = 'ShipConfirmView';
}

class ShipConfirmViewArgs {
  const ShipConfirmViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'ShipConfirmViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i15.ChatHomeView]
class ChatHomeViewRoute extends _i20.PageRouteInfo<ChatHomeViewArgs> {
  ChatHomeViewRoute({_i22.Key? key})
      : super(
          ChatHomeViewRoute.name,
          path: 'chat',
          args: ChatHomeViewArgs(key: key),
        );

  static const String name = 'ChatHomeView';
}

class ChatHomeViewArgs {
  const ChatHomeViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'ChatHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i16.SettingsCredentialsView]
class SettingsCredentialsViewRoute
    extends _i20.PageRouteInfo<SettingsCredentialsViewArgs> {
  SettingsCredentialsViewRoute({_i22.Key? key})
      : super(
          SettingsCredentialsViewRoute.name,
          path: 'settings',
          args: SettingsCredentialsViewArgs(key: key),
        );

  static const String name = 'SettingsCredentialsView';
}

class SettingsCredentialsViewArgs {
  const SettingsCredentialsViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'SettingsCredentialsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i17.SettingsDevicesView]
class SettingsDevicesViewRoute
    extends _i20.PageRouteInfo<SettingsDevicesViewArgs> {
  SettingsDevicesViewRoute({_i22.Key? key})
      : super(
          SettingsDevicesViewRoute.name,
          path: 'settings/devices',
          args: SettingsDevicesViewArgs(key: key),
        );

  static const String name = 'SettingsDevicesView';
}

class SettingsDevicesViewArgs {
  const SettingsDevicesViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'SettingsDevicesViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i18.SettingsKitsView]
class SettingsKitsViewRoute extends _i20.PageRouteInfo<SettingsKitsViewArgs> {
  SettingsKitsViewRoute({_i22.Key? key})
      : super(
          SettingsKitsViewRoute.name,
          path: 'settings/kits',
          args: SettingsKitsViewArgs(key: key),
        );

  static const String name = 'SettingsKitsView';
}

class SettingsKitsViewArgs {
  const SettingsKitsViewArgs({this.key});

  final _i22.Key? key;

  @override
  String toString() {
    return 'SettingsKitsViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i19.RouterService {
  Future<dynamic> navigateToStartupView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      StartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToAppShellView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      AppShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToUnknownView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      UnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedProjectsHomeViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ProjectsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedProjectsNewViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ProjectsNewViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedIntakeWizardViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      IntakeWizardViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignDirectionsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignDirectionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignSurfaceViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignSurfaceViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedDesignApproveViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      DesignApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildRunViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildRunViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildFindingViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildFindingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedBuildApproveViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      BuildApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedShipTargetsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShipTargetsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedShipConfirmViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShipConfirmViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedChatHomeViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ChatHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsCredentialsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsCredentialsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsDevicesViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsDevicesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToNestedSettingsKitsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsKitsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithStartupView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      StartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithAppShellView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      AppShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithUnknownView({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      UnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedProjectsHomeViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ProjectsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedProjectsNewViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ProjectsNewViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedIntakeWizardViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      IntakeWizardViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignDirectionsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignDirectionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignSurfaceViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignSurfaceViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedDesignApproveViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      DesignApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildRunViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildRunViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildFindingViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildFindingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedBuildApproveViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      BuildApproveViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedShipTargetsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShipTargetsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedShipConfirmViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShipConfirmViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedChatHomeViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ChatHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsCredentialsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsCredentialsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsDevicesViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsDevicesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithNestedSettingsKitsViewInAppShellViewRouter({
    _i22.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsKitsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
