// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedRouterGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter/material.dart' as _i21;
import 'package:stacked/stacked.dart' as _i20;
import 'package:stacked_services/stacked_services.dart' as _i19;

import '../ui/views/showcase_application_hub/showcase_application_hub_view.dart'
    as _i2;
import '../ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart'
    as _i9;
import '../ui/views/showcase_home_shell/showcase_home_shell_view.dart' as _i5;
import '../ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_view.dart'
    as _i17;
import '../ui/views/showcase_notes_shell/showcase_notes/showcase_notes_view.dart'
    as _i15;
import '../ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart'
    as _i16;
import '../ui/views/showcase_notes_shell/showcase_notes_shell_view.dart' as _i8;
import '../ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart'
    as _i14;
import '../ui/views/showcase_profile_shell/showcase_maps/showcase_maps_view.dart'
    as _i13;
import '../ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart'
    as _i12;
import '../ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart'
    as _i11;
import '../ui/views/showcase_profile_shell/showcase_profile_shell_view.dart'
    as _i7;
import '../ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart'
    as _i10;
import '../ui/views/showcase_search_shell/showcase_search_shell_view.dart'
    as _i6;
import '../ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.dart'
    as _i4;
import '../ui/views/showcase_startup_shell/showcase_startup_shell_view.dart'
    as _i1;
import '../ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.dart'
    as _i18;
import '../ui/views/showcase_unknown_shell/showcase_unknown_shell_view.dart'
    as _i3;

final stackedRouter =
    StackedRouterWeb(navigatorKey: _i19.StackedService.navigatorKey);

class StackedRouterWeb extends _i20.RootStackRouter {
  StackedRouterWeb({_i21.GlobalKey<_i21.NavigatorState>? navigatorKey})
      : super(navigatorKey);

  @override
  final Map<String, _i20.PageFactory> pagesMap = {
    ShowcaseStartupShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseStartupShellViewArgs>(
          orElse: () => const ShowcaseStartupShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i1.ShowcaseStartupShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseApplicationHubViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseApplicationHubViewArgs>(
          orElse: () => const ShowcaseApplicationHubViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i2.ShowcaseApplicationHubView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseUnknownShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseUnknownShellViewArgs>(
          orElse: () => const ShowcaseUnknownShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i3.ShowcaseUnknownShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseStartupViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseStartupViewArgs>(
          orElse: () => const ShowcaseStartupViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i4.ShowcaseStartupView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseHomeShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseHomeShellViewArgs>(
          orElse: () => const ShowcaseHomeShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i5.ShowcaseHomeShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseSearchShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseSearchShellViewArgs>(
          orElse: () => const ShowcaseSearchShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i6.ShowcaseSearchShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseProfileShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseProfileShellViewArgs>(
          orElse: () => const ShowcaseProfileShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i7.ShowcaseProfileShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesShellViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesShellViewArgs>(
          orElse: () => const ShowcaseNotesShellViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i8.ShowcaseNotesShellView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseHomeViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseHomeViewArgs>(
          orElse: () => const ShowcaseHomeViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i9.ShowcaseHomeView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseSearchViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseSearchViewArgs>(
          orElse: () => const ShowcaseSearchViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i10.ShowcaseSearchView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseProfileViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseProfileViewArgs>(
          orElse: () => const ShowcaseProfileViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i11.ShowcaseProfileView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseMotionViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseMotionViewArgs>(
          orElse: () => const ShowcaseMotionViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i12.ShowcaseMotionView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseMapsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseMapsViewArgs>(
          orElse: () => const ShowcaseMapsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i13.ShowcaseMapsView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseComponentsViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseComponentsViewArgs>(
          orElse: () => const ShowcaseComponentsViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i14.ShowcaseComponentsView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesViewArgs>(
          orElse: () => const ShowcaseNotesViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i15.ShowcaseNotesView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNotesFolderViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNotesFolderViewArgs>(
          orElse: () => const ShowcaseNotesFolderViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i16.ShowcaseNotesFolderView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseNoteEditorViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseNoteEditorViewArgs>(
          orElse: () => const ShowcaseNoteEditorViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i17.ShowcaseNoteEditorView(key: args.key),
        opaque: true,
      );
    },
    ShowcaseUnknownViewRoute.name: (routeData) {
      final args = routeData.argsAs<ShowcaseUnknownViewArgs>(
          orElse: () => const ShowcaseUnknownViewArgs());
      return _i20.AdaptivePage<dynamic>(
        routeData: routeData,
        child: _i18.ShowcaseUnknownView(key: args.key),
        opaque: true,
      );
    },
  };

  @override
  List<_i20.RouteConfig> get routes => [
        _i20.RouteConfig(
          ShowcaseStartupShellViewRoute.name,
          path: '/',
          children: [
            _i20.RouteConfig(
              ShowcaseStartupViewRoute.name,
              path: '',
              parent: ShowcaseStartupShellViewRoute.name,
            )
          ],
        ),
        _i20.RouteConfig(
          ShowcaseApplicationHubViewRoute.name,
          path: '/',
          children: [
            _i20.RouteConfig(
              '#redirect',
              path: '',
              parent: ShowcaseApplicationHubViewRoute.name,
              redirectTo: 'home',
              fullMatch: true,
            ),
            _i20.RouteConfig(
              ShowcaseHomeShellViewRoute.name,
              path: 'home',
              parent: ShowcaseApplicationHubViewRoute.name,
              children: [
                _i20.RouteConfig(
                  ShowcaseHomeViewRoute.name,
                  path: '',
                  parent: ShowcaseHomeShellViewRoute.name,
                )
              ],
            ),
            _i20.RouteConfig(
              ShowcaseSearchShellViewRoute.name,
              path: 'search',
              parent: ShowcaseApplicationHubViewRoute.name,
              children: [
                _i20.RouteConfig(
                  ShowcaseSearchViewRoute.name,
                  path: '',
                  parent: ShowcaseSearchShellViewRoute.name,
                )
              ],
            ),
            _i20.RouteConfig(
              ShowcaseProfileShellViewRoute.name,
              path: 'profile',
              parent: ShowcaseApplicationHubViewRoute.name,
              children: [
                _i20.RouteConfig(
                  ShowcaseProfileViewRoute.name,
                  path: '',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i20.RouteConfig(
                  ShowcaseMotionViewRoute.name,
                  path: 'motion',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i20.RouteConfig(
                  ShowcaseMapsViewRoute.name,
                  path: 'maps',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
                _i20.RouteConfig(
                  ShowcaseComponentsViewRoute.name,
                  path: 'components',
                  parent: ShowcaseProfileShellViewRoute.name,
                ),
              ],
            ),
            _i20.RouteConfig(
              ShowcaseNotesShellViewRoute.name,
              path: 'notes',
              parent: ShowcaseApplicationHubViewRoute.name,
              children: [
                _i20.RouteConfig(
                  ShowcaseNotesViewRoute.name,
                  path: '',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
                _i20.RouteConfig(
                  ShowcaseNotesFolderViewRoute.name,
                  path: 'folder/:id',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
                _i20.RouteConfig(
                  ShowcaseNoteEditorViewRoute.name,
                  path: 'note/:id',
                  parent: ShowcaseNotesShellViewRoute.name,
                ),
              ],
            ),
          ],
        ),
        _i20.RouteConfig(
          ShowcaseUnknownShellViewRoute.name,
          path: '/404',
          children: [
            _i20.RouteConfig(
              ShowcaseUnknownViewRoute.name,
              path: '',
              parent: ShowcaseUnknownShellViewRoute.name,
            )
          ],
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
/// [_i1.ShowcaseStartupShellView]
class ShowcaseStartupShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseStartupShellViewArgs> {
  ShowcaseStartupShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
          ShowcaseStartupShellViewRoute.name,
          path: '/',
          args: ShowcaseStartupShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseStartupShellView';
}

class ShowcaseStartupShellViewArgs {
  const ShowcaseStartupShellViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseStartupShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i2.ShowcaseApplicationHubView]
class ShowcaseApplicationHubViewRoute
    extends _i20.PageRouteInfo<ShowcaseApplicationHubViewArgs> {
  ShowcaseApplicationHubViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
          ShowcaseApplicationHubViewRoute.name,
          path: '/',
          args: ShowcaseApplicationHubViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseApplicationHubView';
}

class ShowcaseApplicationHubViewArgs {
  const ShowcaseApplicationHubViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseApplicationHubViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i3.ShowcaseUnknownShellView]
class ShowcaseUnknownShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseUnknownShellViewArgs> {
  ShowcaseUnknownShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
          ShowcaseUnknownShellViewRoute.name,
          path: '/404',
          args: ShowcaseUnknownShellViewArgs(key: key),
          initialChildren: children,
        );

  static const String name = 'ShowcaseUnknownShellView';
}

class ShowcaseUnknownShellViewArgs {
  const ShowcaseUnknownShellViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseUnknownShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i4.ShowcaseStartupView]
class ShowcaseStartupViewRoute
    extends _i20.PageRouteInfo<ShowcaseStartupViewArgs> {
  ShowcaseStartupViewRoute({_i21.Key? key})
      : super(
          ShowcaseStartupViewRoute.name,
          path: '',
          args: ShowcaseStartupViewArgs(key: key),
        );

  static const String name = 'ShowcaseStartupView';
}

class ShowcaseStartupViewArgs {
  const ShowcaseStartupViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseStartupViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i5.ShowcaseHomeShellView]
class ShowcaseHomeShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseHomeShellViewArgs> {
  ShowcaseHomeShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseHomeShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i6.ShowcaseSearchShellView]
class ShowcaseSearchShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseSearchShellViewArgs> {
  ShowcaseSearchShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseSearchShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i7.ShowcaseProfileShellView]
class ShowcaseProfileShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseProfileShellViewArgs> {
  ShowcaseProfileShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseProfileShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i8.ShowcaseNotesShellView]
class ShowcaseNotesShellViewRoute
    extends _i20.PageRouteInfo<ShowcaseNotesShellViewArgs> {
  ShowcaseNotesShellViewRoute({
    _i21.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesShellViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i9.ShowcaseHomeView]
class ShowcaseHomeViewRoute extends _i20.PageRouteInfo<ShowcaseHomeViewArgs> {
  ShowcaseHomeViewRoute({_i21.Key? key})
      : super(
          ShowcaseHomeViewRoute.name,
          path: '',
          args: ShowcaseHomeViewArgs(key: key),
        );

  static const String name = 'ShowcaseHomeView';
}

class ShowcaseHomeViewArgs {
  const ShowcaseHomeViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseHomeViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i10.ShowcaseSearchView]
class ShowcaseSearchViewRoute
    extends _i20.PageRouteInfo<ShowcaseSearchViewArgs> {
  ShowcaseSearchViewRoute({_i21.Key? key})
      : super(
          ShowcaseSearchViewRoute.name,
          path: '',
          args: ShowcaseSearchViewArgs(key: key),
        );

  static const String name = 'ShowcaseSearchView';
}

class ShowcaseSearchViewArgs {
  const ShowcaseSearchViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseSearchViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i11.ShowcaseProfileView]
class ShowcaseProfileViewRoute
    extends _i20.PageRouteInfo<ShowcaseProfileViewArgs> {
  ShowcaseProfileViewRoute({_i21.Key? key})
      : super(
          ShowcaseProfileViewRoute.name,
          path: '',
          args: ShowcaseProfileViewArgs(key: key),
        );

  static const String name = 'ShowcaseProfileView';
}

class ShowcaseProfileViewArgs {
  const ShowcaseProfileViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseProfileViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i12.ShowcaseMotionView]
class ShowcaseMotionViewRoute
    extends _i20.PageRouteInfo<ShowcaseMotionViewArgs> {
  ShowcaseMotionViewRoute({_i21.Key? key})
      : super(
          ShowcaseMotionViewRoute.name,
          path: 'motion',
          args: ShowcaseMotionViewArgs(key: key),
        );

  static const String name = 'ShowcaseMotionView';
}

class ShowcaseMotionViewArgs {
  const ShowcaseMotionViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseMotionViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i13.ShowcaseMapsView]
class ShowcaseMapsViewRoute extends _i20.PageRouteInfo<ShowcaseMapsViewArgs> {
  ShowcaseMapsViewRoute({_i21.Key? key})
      : super(
          ShowcaseMapsViewRoute.name,
          path: 'maps',
          args: ShowcaseMapsViewArgs(key: key),
        );

  static const String name = 'ShowcaseMapsView';
}

class ShowcaseMapsViewArgs {
  const ShowcaseMapsViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseMapsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i14.ShowcaseComponentsView]
class ShowcaseComponentsViewRoute
    extends _i20.PageRouteInfo<ShowcaseComponentsViewArgs> {
  ShowcaseComponentsViewRoute({_i21.Key? key})
      : super(
          ShowcaseComponentsViewRoute.name,
          path: 'components',
          args: ShowcaseComponentsViewArgs(key: key),
        );

  static const String name = 'ShowcaseComponentsView';
}

class ShowcaseComponentsViewArgs {
  const ShowcaseComponentsViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseComponentsViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i15.ShowcaseNotesView]
class ShowcaseNotesViewRoute extends _i20.PageRouteInfo<ShowcaseNotesViewArgs> {
  ShowcaseNotesViewRoute({_i21.Key? key})
      : super(
          ShowcaseNotesViewRoute.name,
          path: '',
          args: ShowcaseNotesViewArgs(key: key),
        );

  static const String name = 'ShowcaseNotesView';
}

class ShowcaseNotesViewArgs {
  const ShowcaseNotesViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i16.ShowcaseNotesFolderView]
class ShowcaseNotesFolderViewRoute
    extends _i20.PageRouteInfo<ShowcaseNotesFolderViewArgs> {
  ShowcaseNotesFolderViewRoute({_i21.Key? key})
      : super(
          ShowcaseNotesFolderViewRoute.name,
          path: 'folder/:id',
          args: ShowcaseNotesFolderViewArgs(key: key),
        );

  static const String name = 'ShowcaseNotesFolderView';
}

class ShowcaseNotesFolderViewArgs {
  const ShowcaseNotesFolderViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseNotesFolderViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i17.ShowcaseNoteEditorView]
class ShowcaseNoteEditorViewRoute
    extends _i20.PageRouteInfo<ShowcaseNoteEditorViewArgs> {
  ShowcaseNoteEditorViewRoute({_i21.Key? key})
      : super(
          ShowcaseNoteEditorViewRoute.name,
          path: 'note/:id',
          args: ShowcaseNoteEditorViewArgs(key: key),
        );

  static const String name = 'ShowcaseNoteEditorView';
}

class ShowcaseNoteEditorViewArgs {
  const ShowcaseNoteEditorViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseNoteEditorViewArgs{key: $key}';
  }
}

/// generated route for
/// [_i18.ShowcaseUnknownView]
class ShowcaseUnknownViewRoute
    extends _i20.PageRouteInfo<ShowcaseUnknownViewArgs> {
  ShowcaseUnknownViewRoute({_i21.Key? key})
      : super(
          ShowcaseUnknownViewRoute.name,
          path: '',
          args: ShowcaseUnknownViewArgs(key: key),
        );

  static const String name = 'ShowcaseUnknownView';
}

class ShowcaseUnknownViewArgs {
  const ShowcaseUnknownViewArgs({this.key});

  final _i21.Key? key;

  @override
  String toString() {
    return 'ShowcaseUnknownViewArgs{key: $key}';
  }
}

extension RouterStateExtension on _i19.RouterService {
  Future<dynamic> navigateToShowcaseStartupShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseStartupShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseApplicationHubView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseApplicationHubViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseUnknownShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseUnknownShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseStartupViewInShowcaseStartupShellViewRouter({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseHomeShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseHomeShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseSearchShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseSearchShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseProfileShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseProfileShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> navigateToShowcaseNotesShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseNoteEditorViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      navigateToNestedShowcaseUnknownViewInShowcaseUnknownShellViewRouter({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return navigateTo(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseStartupShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseStartupShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseApplicationHubView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseApplicationHubViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseUnknownShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseUnknownShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseStartupViewInShowcaseStartupShellViewRouter({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseStartupViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseHomeShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseHomeShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseSearchShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseSearchShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseProfileShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseProfileShellViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic> replaceWithShowcaseNotesShellView({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
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
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseNoteEditorViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }

  Future<dynamic>
      replaceWithNestedShowcaseUnknownViewInShowcaseUnknownShellViewRouter({
    _i21.Key? key,
    void Function(_i20.NavigationFailure)? onFailure,
  }) async {
    return replaceWith(
      ShowcaseUnknownViewRoute(
        key: key,
      ),
      onFailure: onFailure,
    );
  }
}
