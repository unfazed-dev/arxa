// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i9;
import 'package:stacked/stacked.dart' as _i8;
import 'package:stacked_services/stacked_services.dart' as _i7;

import '../ui/views/approvals_shell/approvals_list/approvals_list_view.dart'
    as _i5;
import '../ui/views/pairing_shell/pairing_connecting/pairing_connecting_view.dart'
    as _i2;
import '../ui/views/pairing_shell/pairing_push_permission/pairing_push_permission_view.dart'
    as _i3;
import '../ui/views/pairing_shell/pairing_scan/pairing_scan_view.dart' as _i1;
import '../ui/views/settings_shell/settings_home/settings_home_view.dart'
    as _i6;
import '../ui/views/studio_shell/studio_session/studio_session_view.dart'
    as _i4;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i7.StackedService.navigatorKey);

class StackedRouterWeb extends _i8.RootStackRouter {
  StackedRouterWeb({_i9.GlobalKey<_i9.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i8.PageFactory> pagesMap = {
    PairingScanViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingScanViewArgs>(
          orElse: () => const PairingScanViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.PairingScanView(key: args.key),
        opaque: true,
      );
    },
    PairingConnectingViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingConnectingViewArgs>(
          orElse: () => const PairingConnectingViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.PairingConnectingView(key: args.key),
        opaque: true,
      );
    },
    PairingPushPermissionViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingPushPermissionViewArgs>(
          orElse: () => const PairingPushPermissionViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.PairingPushPermissionView(key: args.key),
        opaque: true,
      );
    },
    StudioSessionViewRoute.name: (routeData) {
      final args = routeData.argsAs<StudioSessionViewArgs>(
          orElse: () => const StudioSessionViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.StudioSessionView(key: args.key),
        opaque: true,
      );
    },
    ApprovalsListViewRoute.name: (routeData) {
      final args = routeData.argsAs<ApprovalsListViewArgs>(
          orElse: () => const ApprovalsListViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ApprovalsListView(key: args.key),
        opaque: true,
      );
    },
    SettingsHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsHomeViewArgs>(
          orElse: () => const SettingsHomeViewArgs());
      return _i8.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.SettingsHomeView(key: args.key),
        opaque: true,
      );
    },
  };

  @override
  List<_i8.RouteConfig> get routes => [
        _i8.RouteConfig(
          PairingScanViewRoute.name,
          path: '/',
        ),
        _i8.RouteConfig(
          PairingConnectingViewRoute.name,
          path: '/pairing-connecting-view',
        ),
        _i8.RouteConfig(
          PairingPushPermissionViewRoute.name,
          path: '/pairing-push-permission-view',
        ),
        _i8.RouteConfig(
          StudioSessionViewRoute.name,
          path: '/studio-session-view',
        ),
        _i8.RouteConfig(
          ApprovalsListViewRoute.name,
          path: '/approvals-list-view',
        ),
        _i8.RouteConfig(
          SettingsHomeViewRoute.name,
          path: '/settings-home-view',
        ),
      ];
}

/// generated route for
/// [_i1.PairingScanView]
class PairingScanViewRoute extends _i8.PageRouteInfo<PairingScanViewArgs> {
  PairingScanViewRoute({_i9.Key? key})
      : super(
          PairingScanViewRoute.name,
          path: '/',
          args: PairingScanViewArgs(key: key),
        );

  static const String name = 'PairingScanView';
}

class PairingScanViewArgs {
  const PairingScanViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'PairingScanViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.PairingConnectingView]
class PairingConnectingViewRoute
    extends _i8.PageRouteInfo<PairingConnectingViewArgs> {
  PairingConnectingViewRoute({_i9.Key? key})
      : super(
          PairingConnectingViewRoute.name,
          path: '/pairing-connecting-view',
          args: PairingConnectingViewArgs(key: key),
        );

  static const String name = 'PairingConnectingView';
}

class PairingConnectingViewArgs {
  const PairingConnectingViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'PairingConnectingViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.PairingPushPermissionView]
class PairingPushPermissionViewRoute
    extends _i8.PageRouteInfo<PairingPushPermissionViewArgs> {
  PairingPushPermissionViewRoute({_i9.Key? key})
      : super(
          PairingPushPermissionViewRoute.name,
          path: '/pairing-push-permission-view',
          args: PairingPushPermissionViewArgs(key: key),
        );

  static const String name = 'PairingPushPermissionView';
}

class PairingPushPermissionViewArgs {
  const PairingPushPermissionViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'PairingPushPermissionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.StudioSessionView]
class StudioSessionViewRoute extends _i8.PageRouteInfo<StudioSessionViewArgs> {
  StudioSessionViewRoute({_i9.Key? key})
      : super(
          StudioSessionViewRoute.name,
          path: '/studio-session-view',
          args: StudioSessionViewArgs(key: key),
        );

  static const String name = 'StudioSessionView';
}

class StudioSessionViewArgs {
  const StudioSessionViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'StudioSessionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ApprovalsListView]
class ApprovalsListViewRoute extends _i8.PageRouteInfo<ApprovalsListViewArgs> {
  ApprovalsListViewRoute({_i9.Key? key})
      : super(
          ApprovalsListViewRoute.name,
          path: '/approvals-list-view',
          args: ApprovalsListViewArgs(key: key),
        );

  static const String name = 'ApprovalsListView';
}

class ApprovalsListViewArgs {
  const ApprovalsListViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'ApprovalsListViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.SettingsHomeView]
class SettingsHomeViewRoute extends _i8.PageRouteInfo<SettingsHomeViewArgs> {
  SettingsHomeViewRoute({_i9.Key? key})
      : super(
          SettingsHomeViewRoute.name,
          path: '/settings-home-view',
          args: SettingsHomeViewArgs(key: key),
        );

  static const String name = 'SettingsHomeView';
}

class SettingsHomeViewArgs {
  const SettingsHomeViewArgs({this.key});

  final _i9.Key? key;

  @override
  String toString() {
    return 'SettingsHomeViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i7.RouterService {
  Future<dynamic> navigateToPairingScanView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingScanViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToPairingConnectingView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingConnectingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToPairingPushPermissionView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingPushPermissionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToStudioSessionView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      StudioSessionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToApprovalsListView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ApprovalsListViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToSettingsHomeView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingScanView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingScanViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingConnectingView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingConnectingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingPushPermissionView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingPushPermissionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithStudioSessionView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      StudioSessionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithApprovalsListView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ApprovalsListViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithSettingsHomeView({
    _i9.Key? key,
    void Function(_i8.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
