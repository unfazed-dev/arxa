// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i11;
import 'package:stacked/stacked.dart' as _i10;
import 'package:stacked_services/stacked_services.dart' as _i9;

import '../ui/views/approvals_shell/approvals_list/approvals_list_view.dart'
    as _i5;
import '../ui/views/code_shell/code_conversation/code_conversation_view.dart'
    as _i8;
import '../ui/views/code_shell/code_sessions/code_sessions_view.dart' as _i7;
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
    StackedRouterWeb(navigatorKey: _i9.StackedService.navigatorKey);

class StackedRouterWeb extends _i10.RootStackRouter {
  StackedRouterWeb({_i11.GlobalKey<_i11.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i10.PageFactory> pagesMap = {
    PairingScanViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingScanViewArgs>(
          orElse: () => const PairingScanViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.PairingScanView(key: args.key),
        opaque: true,
      );
    },
    PairingConnectingViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingConnectingViewArgs>(
          orElse: () => const PairingConnectingViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.PairingConnectingView(key: args.key),
        opaque: true,
      );
    },
    PairingPushPermissionViewRoute.name: (routeData) {
      final args = routeData.argsAs<PairingPushPermissionViewArgs>(
          orElse: () => const PairingPushPermissionViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.PairingPushPermissionView(key: args.key),
        opaque: true,
      );
    },
    StudioSessionViewRoute.name: (routeData) {
      final args = routeData.argsAs<StudioSessionViewArgs>(
          orElse: () => const StudioSessionViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.StudioSessionView(key: args.key),
        opaque: true,
      );
    },
    ApprovalsListViewRoute.name: (routeData) {
      final args = routeData.argsAs<ApprovalsListViewArgs>(
          orElse: () => const ApprovalsListViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ApprovalsListView(key: args.key),
        opaque: true,
      );
    },
    SettingsHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<SettingsHomeViewArgs>(
          orElse: () => const SettingsHomeViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.SettingsHomeView(key: args.key),
        opaque: true,
      );
    },
    CodeSessionsViewRoute.name: (routeData) {
      final args = routeData.argsAs<CodeSessionsViewArgs>(
          orElse: () => const CodeSessionsViewArgs());
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i7.CodeSessionsView(key: args.key),
        opaque: true,
      );
    },
    CodeConversationViewRoute.name: (routeData) {
      final args = routeData.argsAs<CodeConversationViewArgs>();
      return _i10.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i8.CodeConversationView(
          sessionId: args.sessionId,
          key: args.key,
        ),
        opaque: true,
      );
    },
  };

  @override
  List<_i10.RouteConfig> get routes => [
        _i10.RouteConfig(
          PairingScanViewRoute.name,
          path: '/',
        ),
        _i10.RouteConfig(
          PairingConnectingViewRoute.name,
          path: '/pairing-connecting-view',
        ),
        _i10.RouteConfig(
          PairingPushPermissionViewRoute.name,
          path: '/pairing-push-permission-view',
        ),
        _i10.RouteConfig(
          StudioSessionViewRoute.name,
          path: '/studio-session-view',
        ),
        _i10.RouteConfig(
          ApprovalsListViewRoute.name,
          path: '/approvals-list-view',
        ),
        _i10.RouteConfig(
          SettingsHomeViewRoute.name,
          path: '/settings-home-view',
        ),
        _i10.RouteConfig(
          CodeSessionsViewRoute.name,
          path: '/code-sessions-view',
        ),
        _i10.RouteConfig(
          CodeConversationViewRoute.name,
          path: '/code-conversation-view',
        ),
      ];
}

/// generated route for
/// [_i1.PairingScanView]
class PairingScanViewRoute extends _i10.PageRouteInfo<PairingScanViewArgs> {
  PairingScanViewRoute({_i11.Key? key})
      : super(
          PairingScanViewRoute.name,
          path: '/',
          args: PairingScanViewArgs(key: key),
        );

  static const String name = 'PairingScanView';
}

class PairingScanViewArgs {
  const PairingScanViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'PairingScanViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.PairingConnectingView]
class PairingConnectingViewRoute
    extends _i10.PageRouteInfo<PairingConnectingViewArgs> {
  PairingConnectingViewRoute({_i11.Key? key})
      : super(
          PairingConnectingViewRoute.name,
          path: '/pairing-connecting-view',
          args: PairingConnectingViewArgs(key: key),
        );

  static const String name = 'PairingConnectingView';
}

class PairingConnectingViewArgs {
  const PairingConnectingViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'PairingConnectingViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.PairingPushPermissionView]
class PairingPushPermissionViewRoute
    extends _i10.PageRouteInfo<PairingPushPermissionViewArgs> {
  PairingPushPermissionViewRoute({_i11.Key? key})
      : super(
          PairingPushPermissionViewRoute.name,
          path: '/pairing-push-permission-view',
          args: PairingPushPermissionViewArgs(key: key),
        );

  static const String name = 'PairingPushPermissionView';
}

class PairingPushPermissionViewArgs {
  const PairingPushPermissionViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'PairingPushPermissionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.StudioSessionView]
class StudioSessionViewRoute extends _i10.PageRouteInfo<StudioSessionViewArgs> {
  StudioSessionViewRoute({_i11.Key? key})
      : super(
          StudioSessionViewRoute.name,
          path: '/studio-session-view',
          args: StudioSessionViewArgs(key: key),
        );

  static const String name = 'StudioSessionView';
}

class StudioSessionViewArgs {
  const StudioSessionViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'StudioSessionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ApprovalsListView]
class ApprovalsListViewRoute extends _i10.PageRouteInfo<ApprovalsListViewArgs> {
  ApprovalsListViewRoute({_i11.Key? key})
      : super(
          ApprovalsListViewRoute.name,
          path: '/approvals-list-view',
          args: ApprovalsListViewArgs(key: key),
        );

  static const String name = 'ApprovalsListView';
}

class ApprovalsListViewArgs {
  const ApprovalsListViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'ApprovalsListViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.SettingsHomeView]
class SettingsHomeViewRoute extends _i10.PageRouteInfo<SettingsHomeViewArgs> {
  SettingsHomeViewRoute({_i11.Key? key})
      : super(
          SettingsHomeViewRoute.name,
          path: '/settings-home-view',
          args: SettingsHomeViewArgs(key: key),
        );

  static const String name = 'SettingsHomeView';
}

class SettingsHomeViewArgs {
  const SettingsHomeViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'SettingsHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i7.CodeSessionsView]
class CodeSessionsViewRoute extends _i10.PageRouteInfo<CodeSessionsViewArgs> {
  CodeSessionsViewRoute({_i11.Key? key})
      : super(
          CodeSessionsViewRoute.name,
          path: '/code-sessions-view',
          args: CodeSessionsViewArgs(key: key),
        );

  static const String name = 'CodeSessionsView';
}

class CodeSessionsViewArgs {
  const CodeSessionsViewArgs({this.key});

  final _i11.Key? key;

  @override
  String toString() {
    return 'CodeSessionsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i8.CodeConversationView]
class CodeConversationViewRoute
    extends _i10.PageRouteInfo<CodeConversationViewArgs> {
  CodeConversationViewRoute({
    required String sessionId,
    _i11.Key? key,
  }) : super(
          CodeConversationViewRoute.name,
          path: '/code-conversation-view',
          args: CodeConversationViewArgs(
            sessionId: sessionId,
            key: key,
          ),
        );

  static const String name = 'CodeConversationView';
}

class CodeConversationViewArgs {
  const CodeConversationViewArgs({
    required this.sessionId,
    this.key,
  });

  final String sessionId;

  final _i11.Key? key;

  @override
  String toString() {
    return 'CodeConversationViewArgs{sessionId: $sessionId, key: $key}';
  }
}

extension RouterStateExtension on _i9.RouterService {
  Future<dynamic> navigateToPairingScanView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingScanViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToPairingConnectingView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingConnectingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToPairingPushPermissionView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      PairingPushPermissionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToStudioSessionView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      StudioSessionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToApprovalsListView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ApprovalsListViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToSettingsHomeView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      SettingsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToCodeSessionsView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      CodeSessionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToCodeConversationView({
    required String sessionId,
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      CodeConversationViewRoute(
        sessionId: sessionId,
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingScanView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingScanViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingConnectingView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingConnectingViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithPairingPushPermissionView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      PairingPushPermissionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithStudioSessionView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      StudioSessionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithApprovalsListView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ApprovalsListViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithSettingsHomeView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      SettingsHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithCodeSessionsView({
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      CodeSessionsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithCodeConversationView({
    required String sessionId,
    _i11.Key? key,
    void Function(_i10.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      CodeConversationViewRoute(
        sessionId: sessionId,
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
