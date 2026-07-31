import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:stacked/stacked.dart'
    show
        CupertinoPageX,
        MaterialPageX,
        PageBuilder,
        RouteData,
        RootStackRouter,
        StackedPage;

/// Per-platform native page wrapping for stacked (Navigator 2.0) hosts.
///
/// stacked 3.5.0's `AdaptivePage` builds a material route on ALL non-web
/// platforms — so the iOS edge-swipe-back gesture (which lives only in the
/// cupertino route mixin `CustomCupertinoRouteTransitionMixin`, never in a
/// themed `CupertinoPageTransitionsBuilder`) never attaches. [platform]
/// re-wraps a generated [StackedPage] as a cupertino page on iOS and a material
/// page elsewhere, reusing `routeData` + child so path-params, guards, deep
/// links, and the back-button dispatcher survive — the route stays declarative
/// (no raw `Navigator.push`). Android predictive back also needs
/// `enableOnBackInvokedCallback` in the host manifest; the default Material
/// theme already uses [PredictiveBackPageTransitionsBuilder].
///
/// Apply via [KitPlatformPagesMixin] — see its docs.
class KitPlatformPages {
  const KitPlatformPages._();

  /// Cupertinos [original] on iOS (slide + edge-swipe-back via the cupertino
  /// route mixin) and keeps it material elsewhere (theme-driven → Android
  /// predictive back). Web keeps the generated page as-is (no-animation).
  //
  // ponytail: `opaque`/`title` from the original page are dropped —
  // CupertinoPageX/MaterialPageX don't accept `opaque` (default true) and the
  // generated routes never set `title`. No showcase route uses opaque=false;
  // revisit if one ever does.
  static StackedPage platform(StackedPage original, RouteData data) {
    // Web: keep the generated page — AdaptivePage no-animates on web
    // (URL-driven nav; mobile transitions read wrong on desktop).
    if (kIsWeb) return original;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPageX<dynamic>(
        routeData: data,
        child: original.child,
        fullscreenDialog: original.fullscreenDialog,
        maintainState: original.maintainState,
      );
    }
    return MaterialPageX<dynamic>(
      routeData: data,
      child: original.child,
      fullscreenDialog: original.fullscreenDialog,
      maintainState: original.maintainState,
    );
  }
}

/// Mix into a host's generated router to render every route as a cupertino
/// page on iOS and a material page elsewhere (see [KitPlatformPages] for why).
/// The override propagates to nested tab controllers (built with
/// `pageBuilder: parent.pageBuilder`), so children + grandchildren are covered.
///
/// ```dart
/// class AppRouter extends StackedRouterWeb with KitPlatformPagesMixin {
///   AppRouter({super.navigatorKey});
/// }
/// ```
mixin KitPlatformPagesMixin on RootStackRouter {
  @override
  PageBuilder get pageBuilder => (RouteData data) =>
      KitPlatformPages.platform(super.pageBuilder(data), data);
}
