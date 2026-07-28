// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i6;
import 'package:stacked/stacked.dart' as _i5;
import 'package:stacked_services/stacked_services.dart' as _i4;

import '../ui/views/home/home_view.dart' as _i2;
import '../ui/views/startup/startup_view.dart' as _i1;
import '../ui/views/unknown/unknown_view.dart' as _i3;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i4.StackedService.navigatorKey);

class StackedRouterWeb extends _i5.RootStackRouter {
  StackedRouterWeb({_i6.GlobalKey<_i6.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i5.PageFactory> pagesMap = {
    StartupViewRoute.name: (routeData) {
      final args = routeData.argsAs<StartupViewArgs>(
          orElse: () => const StartupViewArgs());
      return _i5.CustomPage<dynamic>(
        routeData: routeData,
        child: _i1.StartupView(key: args.key),
        opaque: true,
        barrierDismissible: false,
      );
    },
    HomeViewRoute.name: (routeData) {
      final args =
          routeData.argsAs<HomeViewArgs>(orElse: () => const HomeViewArgs());
      return _i5.CustomPage<dynamic>(
        routeData: routeData,
        child: _i2.HomeView(key: args.key),
        opaque: true,
        barrierDismissible: false,
      );
    },
    UnknownViewRoute.name: (routeData) {
      final args = routeData.argsAs<UnknownViewArgs>(
          orElse: () => const UnknownViewArgs());
      return _i5.CustomPage<dynamic>(
        routeData: routeData,
        child: _i3.UnknownView(key: args.key),
        opaque: true,
        barrierDismissible: false,
      );
    },
  };

  @override
  List<_i5.RouteConfig> get routes => [
        _i5.RouteConfig(
          StartupViewRoute.name,
          path: '/',
        ),
        _i5.RouteConfig(
          HomeViewRoute.name,
          path: '/home-view',
        ),
        _i5.RouteConfig(
          UnknownViewRoute.name,
          path: '/404',
        ),
        _i5.RouteConfig(
          '*#redirect',
          path: '*',
          redirectTo: '/404',
          fullMatch: true,
        ),
      ];
}

/// generated route for
/// [_i1.StartupView]
class StartupViewRoute extends _i5.PageRouteInfo<StartupViewArgs> {
  StartupViewRoute({_i6.Key? key})
      : super(
          StartupViewRoute.name,
          path: '/',
          args: StartupViewArgs(key: key),
        );

  static const String name = 'StartupView';
}

class StartupViewArgs {
  const StartupViewArgs({this.key});

  final _i6.Key? key;

  @override
  String toString() {
    return 'StartupViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.HomeView]
class HomeViewRoute extends _i5.PageRouteInfo<HomeViewArgs> {
  HomeViewRoute({_i6.Key? key})
      : super(
          HomeViewRoute.name,
          path: '/home-view',
          args: HomeViewArgs(key: key),
        );

  static const String name = 'HomeView';
}

class HomeViewArgs {
  const HomeViewArgs({this.key});

  final _i6.Key? key;

  @override
  String toString() {
    return 'HomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.UnknownView]
class UnknownViewRoute extends _i5.PageRouteInfo<UnknownViewArgs> {
  UnknownViewRoute({_i6.Key? key})
      : super(
          UnknownViewRoute.name,
          path: '/404',
          args: UnknownViewArgs(key: key),
        );

  static const String name = 'UnknownView';
}

class UnknownViewArgs {
  const UnknownViewArgs({this.key});

  final _i6.Key? key;

  @override
  String toString() {
    return 'UnknownViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i4.RouterService {
  Future<dynamic> navigateToStartupView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      StartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToHomeView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      HomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToUnknownView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      UnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithStartupView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      StartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithHomeView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      HomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithUnknownView({
    _i6.Key? key,
    void Function(_i5.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      UnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
