// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i19;
import 'package:stacked/stacked.dart' as _i18;
import 'package:stacked_services/stacked_services.dart' as _i17;

import '../ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart'
    as _i8;
import '../ui/views/showcase_home_shell/showcase_home_shell_view.dart' as _i4;
import '../ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.dart'
    as _i16;
import '../ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart'
    as _i14;
import '../ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart'
    as _i15;
import '../ui/views/showcase_notes_shell/showcase_notes_shell_view.dart' as _i7;
import '../ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart'
    as _i13;
import '../ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.dart'
    as _i12;
import '../ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart'
    as _i11;
import '../ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart'
    as _i10;
import '../ui/views/showcase_profile_shell/showcase_profile_shell_view.dart'
    as _i6;
import '../ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart'
    as _i9;
import '../ui/views/showcase_search_shell/showcase_search_shell_view.dart'
    as _i5;
import '../ui/views/showcase_shell/showcase_shell_view.dart' as _i2;
import '../ui/views/showcase_startup/showcase_startup_view.dart' as _i1;
import '../ui/views/showcase_unknown/showcase_unknown_view.dart' as _i3;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i17.StackedService.navigatorKey);

class StackedRouterWeb extends _i18.RootStackRouter {
  StackedRouterWeb({_i19.GlobalKey<_i19.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i18.PageFactory> pagesMap = {
    ShowcaseStartupViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseStartupViewArgs>(
          orElse: () => const ShowcaseStartupViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.ShowcaseStartupView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseShellViewArgs>(
          orElse: () => const ShowcaseShellViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.ShowcaseShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseUnknownViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseUnknownViewArgs>(
          orElse: () => const ShowcaseUnknownViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.ShowcaseUnknownView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseHomeShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseHomeShellViewArgs>(
          orElse: () => const ShowcaseHomeShellViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.ShowcaseHomeShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseSearchShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseSearchShellViewArgs>(
          orElse: () => const ShowcaseSearchShellViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ShowcaseSearchShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseProfileShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseProfileShellViewArgs>(
          orElse: () => const ShowcaseProfileShellViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.ShowcaseProfileShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesShellViewArgs>(
          orElse: () => const ShowcaseNotesShellViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i7.ShowcaseNotesShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseHomeViewArgs>(
          orElse: () => const ShowcaseHomeViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i8.ShowcaseHomeView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseSearchViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseSearchViewArgs>(
          orElse: () => const ShowcaseSearchViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i9.ShowcaseSearchView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseProfileViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseProfileViewArgs>(
          orElse: () => const ShowcaseProfileViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i10.ShowcaseProfileView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseMotionViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseMotionViewArgs>(
          orElse: () => const ShowcaseMotionViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i11.ShowcaseMotionView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseMapsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseMapsViewArgs>(
          orElse: () => const ShowcaseMapsViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i12.ShowcaseMapsView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseComponentsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseComponentsViewArgs>(
          orElse: () => const ShowcaseComponentsViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i13.ShowcaseComponentsView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesViewArgs>(
          orElse: () => const ShowcaseNotesViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i14.ShowcaseNotesView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesFolderViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesFolderViewArgs>(
          orElse: () => const ShowcaseNotesFolderViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i15.ShowcaseNotesFolderView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNoteEditorViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNoteEditorViewArgs>(
          orElse: () => const ShowcaseNoteEditorViewArgs());
      return _i18.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i16.ShowcaseNoteEditorView(key: args.key),
        opaque: true,
      );
    },
  };

  @override
  List<_i18.RouteConfig> get routes => [
        _i18.RouteConfig(
          ShowcaseStartupViewRoute.name,
          path: '/',
        ),
        _i18.RouteConfig(
          ShowcaseShellViewRoute.name,
          path: '/',
          children: [
            _i18.RouteConfig(
              '#redirect',
              path: '',
              parent: ShowcaseShellViewRoute.name,
              redirectTo: 'home',
              fullMatch: true,
            ),
            _i18.RouteConfig(
              ShowcaseHomeShellViewRoute.name,
              path: 'home',
              parent: ShowcaseShellViewRoute.name,
              children: [
                _i18.RouteConfig(
                  ShowcaseHomeViewRoute.name,
                  path: '',
                  parent: ShowcaseHomeShellViewRoute.name,
                )
              ],
            ),
            _i18.RouteConfig(
              ShowcaseSearchShellViewRoute.name,
              path: 'search',
              parent: ShowcaseShellViewRoute.name,
              children: [
                _i18.RouteConfig(
                  ShowcaseSearchViewRoute.name,
                  path: '',
                  parent: ShowcaseSearchShellViewRoute.name,
                )
              ],
            ),
            _i18.RouteConfig(
              ShowcaseProfileShellViewRoute.name,
              path: 'profile',
              parent: ShowcaseShellViewRoute.name,
              children: [
                _i18.RouteConfig(
                  ShowcaseProfileViewRoute.name,
                  path: '',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i18.RouteConfig(
                  ShowcaseMotionViewRoute.name,
                  path: 'motion',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i18.RouteConfig(
                  ShowcaseMapsViewRoute.name,
                  path: 'maps',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i18.RouteConfig(
                  ShowcaseComponentsViewRoute.name,
                  path: 'components',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
              ],
            ),
            _i18.RouteConfig(
              ShowcaseNotesShellViewRoute.name,
              path: 'notes',
              parent: ShowcaseShellViewRoute.name,
              children: [
                _i18.RouteConfig(
                  ShowcaseNotesViewRoute.name,
                  path: '',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
                _i18.RouteConfig(
                  ShowcaseNotesFolderViewRoute.name,
                  path: 'folder/:id',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
                _i18.RouteConfig(
                  ShowcaseNoteEditorViewRoute.name,
                  path: 'note/:id',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
              ],
            ),
          ],
        ),
        _i18.RouteConfig(
          ShowcaseUnknownViewRoute.name,
          path: '/404',
        ),
        _i18.RouteConfig(
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
    extends _i18.PageRouteInfo<ShowcaseStartupViewArgs> {
  ShowcaseStartupViewRoute({_i19.Key? key})
      : super(
          ShowcaseStartupViewRoute.name,
          path: '/',
          args: ShowcaseStartupViewArgs(key: key),
        );

  static const String name = 'ShowcaseStartupView';
}

class ShowcaseStartupViewArgs {
  const ShowcaseStartupViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseStartupViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.ShowcaseShellView]
class ShowcaseShellViewRoute extends _i18.PageRouteInfo<ShowcaseShellViewArgs> {
  ShowcaseShellViewRoute({
    _i19.Key? key,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          ShowcaseShellViewRoute.name,
          path: '/',
          args: ShowcaseShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseShellView';
}

class ShowcaseShellViewArgs {
  const ShowcaseShellViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.ShowcaseUnknownView]
class ShowcaseUnknownViewRoute
    extends _i18.PageRouteInfo<ShowcaseUnknownViewArgs> {
  ShowcaseUnknownViewRoute({_i19.Key? key})
      : super(
          ShowcaseUnknownViewRoute.name,
          path: '/404',
          args: ShowcaseUnknownViewArgs(key: key),
        );

  static const String name = 'ShowcaseUnknownView';
}

class ShowcaseUnknownViewArgs {
  const ShowcaseUnknownViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseUnknownViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.ShowcaseHomeShellView]
class ShowcaseHomeShellViewRoute
    extends _i18.PageRouteInfo<ShowcaseHomeShellViewArgs> {
  ShowcaseHomeShellViewRoute({
    _i19.Key? key,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          ShowcaseHomeShellViewRoute.name,
          path: 'home',
          args: ShowcaseHomeShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseHomeShellView';
}

class ShowcaseHomeShellViewArgs {
  const ShowcaseHomeShellViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseHomeShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ShowcaseSearchShellView]
class ShowcaseSearchShellViewRoute
    extends _i18.PageRouteInfo<ShowcaseSearchShellViewArgs> {
  ShowcaseSearchShellViewRoute({
    _i19.Key? key,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          ShowcaseSearchShellViewRoute.name,
          path: 'search',
          args: ShowcaseSearchShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseSearchShellView';
}

class ShowcaseSearchShellViewArgs {
  const ShowcaseSearchShellViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseSearchShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.ShowcaseProfileShellView]
class ShowcaseProfileShellViewRoute
    extends _i18.PageRouteInfo<ShowcaseProfileShellViewArgs> {
  ShowcaseProfileShellViewRoute({
    _i19.Key? key,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          ShowcaseProfileShellViewRoute.name,
          path: 'profile',
          args: ShowcaseProfileShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseProfileShellView';
}

class ShowcaseProfileShellViewArgs {
  const ShowcaseProfileShellViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseProfileShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i7.ShowcaseNotesShellView]
class ShowcaseNotesShellViewRoute
    extends _i18.PageRouteInfo<ShowcaseNotesShellViewArgs> {
  ShowcaseNotesShellViewRoute({
    _i19.Key? key,
    List<_i18.PageRouteInfo>? children,
  }) : super(
          ShowcaseNotesShellViewRoute.name,
          path: 'notes',
          args: ShowcaseNotesShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseNotesShellView';
}

class ShowcaseNotesShellViewArgs {
  const ShowcaseNotesShellViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i8.ShowcaseHomeView]
class ShowcaseHomeViewRoute extends _i18.PageRouteInfo<ShowcaseHomeViewArgs> {
  ShowcaseHomeViewRoute({_i19.Key? key})
      : super(
          ShowcaseHomeViewRoute.name,
          path: '',
          args: ShowcaseHomeViewArgs(key: key),
        );

  static const String name = 'ShowcaseHomeView';
}

class ShowcaseHomeViewArgs {
  const ShowcaseHomeViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i9.ShowcaseSearchView]
class ShowcaseSearchViewRoute
    extends _i18.PageRouteInfo<ShowcaseSearchViewArgs> {
  ShowcaseSearchViewRoute({_i19.Key? key})
      : super(
          ShowcaseSearchViewRoute.name,
          path: '',
          args: ShowcaseSearchViewArgs(key: key),
        );

  static const String name = 'ShowcaseSearchView';
}

class ShowcaseSearchViewArgs {
  const ShowcaseSearchViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseSearchViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i10.ShowcaseProfileView]
class ShowcaseProfileViewRoute
    extends _i18.PageRouteInfo<ShowcaseProfileViewArgs> {
  ShowcaseProfileViewRoute({_i19.Key? key})
      : super(
          ShowcaseProfileViewRoute.name,
          path: '',
          args: ShowcaseProfileViewArgs(key: key),
        );

  static const String name = 'ShowcaseProfileView';
}

class ShowcaseProfileViewArgs {
  const ShowcaseProfileViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseProfileViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i11.ShowcaseMotionView]
class ShowcaseMotionViewRoute
    extends _i18.PageRouteInfo<ShowcaseMotionViewArgs> {
  ShowcaseMotionViewRoute({_i19.Key? key})
      : super(
          ShowcaseMotionViewRoute.name,
          path: 'motion',
          args: ShowcaseMotionViewArgs(key: key),
        );

  static const String name = 'ShowcaseMotionView';
}

class ShowcaseMotionViewArgs {
  const ShowcaseMotionViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseMotionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i12.ShowcaseMapsView]
class ShowcaseMapsViewRoute extends _i18.PageRouteInfo<ShowcaseMapsViewArgs> {
  ShowcaseMapsViewRoute({_i19.Key? key})
      : super(
          ShowcaseMapsViewRoute.name,
          path: 'maps',
          args: ShowcaseMapsViewArgs(key: key),
        );

  static const String name = 'ShowcaseMapsView';
}

class ShowcaseMapsViewArgs {
  const ShowcaseMapsViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseMapsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i13.ShowcaseComponentsView]
class ShowcaseComponentsViewRoute
    extends _i18.PageRouteInfo<ShowcaseComponentsViewArgs> {
  ShowcaseComponentsViewRoute({_i19.Key? key})
      : super(
          ShowcaseComponentsViewRoute.name,
          path: 'components',
          args: ShowcaseComponentsViewArgs(key: key),
        );

  static const String name = 'ShowcaseComponentsView';
}

class ShowcaseComponentsViewArgs {
  const ShowcaseComponentsViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseComponentsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i14.ShowcaseNotesView]
class ShowcaseNotesViewRoute extends _i18.PageRouteInfo<ShowcaseNotesViewArgs> {
  ShowcaseNotesViewRoute({_i19.Key? key})
      : super(
          ShowcaseNotesViewRoute.name,
          path: '',
          args: ShowcaseNotesViewArgs(key: key),
        );

  static const String name = 'ShowcaseNotesView';
}

class ShowcaseNotesViewArgs {
  const ShowcaseNotesViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i15.ShowcaseNotesFolderView]
class ShowcaseNotesFolderViewRoute
    extends _i18.PageRouteInfo<ShowcaseNotesFolderViewArgs> {
  ShowcaseNotesFolderViewRoute({_i19.Key? key})
      : super(
          ShowcaseNotesFolderViewRoute.name,
          path: 'folder/:id',
          args: ShowcaseNotesFolderViewArgs(key: key),
        );

  static const String name = 'ShowcaseNotesFolderView';
}

class ShowcaseNotesFolderViewArgs {
  const ShowcaseNotesFolderViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesFolderViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i16.ShowcaseNoteEditorView]
class ShowcaseNoteEditorViewRoute
    extends _i18.PageRouteInfo<ShowcaseNoteEditorViewArgs> {
  ShowcaseNoteEditorViewRoute({_i19.Key? key})
      : super(
          ShowcaseNoteEditorViewRoute.name,
          path: 'note/:id',
          args: ShowcaseNoteEditorViewArgs(key: key),
        );

  static const String name = 'ShowcaseNoteEditorView';
}

class ShowcaseNoteEditorViewArgs {
  const ShowcaseNoteEditorViewArgs({this.key});

  final _i19.Key? key;

  @override
  String toString() {
    return 'ShowcaseNoteEditorViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i17.RouterService {
  Future<dynamic> navigateToShowcaseStartupView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseUnknownView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseHomeShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseHomeShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseSearchShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseSearchShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseProfileShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseProfileShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseNotesShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseNotesShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseHomeViewInShowcaseHomeShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseSearchViewInShowcaseSearchShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseSearchViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseProfileViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseProfileViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseMotionViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseMotionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseMapsViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseMapsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseComponentsViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseComponentsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseNotesViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseNotesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseNotesFolderViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseNotesFolderViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseNoteEditorViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseNoteEditorViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseStartupView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseUnknownView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseHomeShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseHomeShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseSearchShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseSearchShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseProfileShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseProfileShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseNotesShellView({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseNotesShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseHomeViewInShowcaseHomeShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseHomeViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseSearchViewInShowcaseSearchShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseSearchViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseProfileViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseProfileViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseMotionViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseMotionViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseMapsViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseMapsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseComponentsViewInShowcaseProfileShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseComponentsViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseNotesViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseNotesViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseNotesFolderViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseNotesFolderViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseNoteEditorViewInShowcaseNotesShellViewRouter({
    _i19.Key? key,
    void Function(_i18.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseNoteEditorViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
