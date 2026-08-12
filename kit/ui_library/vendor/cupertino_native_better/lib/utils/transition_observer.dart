import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/widgets.dart';
import '../cupertino_native_platform_interface.dart';

/// A navigation observer that automatically notifies native Cupertino components
/// when route transitions begin and end.
///
/// This prevents visual artifacts with Liquid Glass effects during Flutter
/// navigation transitions.
///
/// ## Usage
///
/// Add this observer to your app's navigatorObservers:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     CNTransitionObserver(),
///   ],
///   // ...
/// )
/// ```
///
/// Or with GoRouter:
///
/// ```dart
/// GoRouter(
///   observers: [
///     CNTransitionObserver(),
///   ],
///   // ...
/// )
/// ```
class CNTransitionObserver extends NavigatorObserver {
  /// Creates a [CNTransitionObserver] instance.
  CNTransitionObserver() {
    _instances.add(this);
  }

  int _transitionCount = 0;

  /// Every constructed observer instance — one per navigator that registered
  /// one (root + each nested router). [NavigatorObserver] has no dispose hook,
  /// so defunct instances are pruned lazily in [hasActiveTransitionAbove]
  /// once their count has drained and their navigator has detached.
  static final Set<CNTransitionObserver> _instances = <CNTransitionObserver>{};

  /// Global count of route transitions in flight across ALL observer instances
  /// (root + nested navigators). This is the Dart-side signal a widget listens
  /// to when it must ALPHA-0 HIDE a native platform view for the duration of a
  /// route slide — the native `beginTransition`/`endTransition` flag only
  /// drives the on-view glass-effect tint, and a hybrid-composition platform
  /// view can't be tinted out of a leak: it must leave the frame's layer tree
  /// (see `AppBoxKitNativeChromeGate`). Includes the interactive back-swipe, held
  /// open by the `didStartUserGesture`/`didStopUserGesture` hooks below —
  /// `didPop` alone fires only at gesture COMMIT, leaving the drag unguarded.
  static final ValueNotifier<int> _activeTransitions = ValueNotifier<int>(0);

  /// Read-only: `> 0` while any route transition (push / pop / replace /
  /// remove, or an interactive back-swipe gesture) is animating — in ANY
  /// navigator, root or nested. Use as a change signal; for the actual
  /// hide decision use [hasActiveTransitionAbove], which scopes the check
  /// to the navigators that can move the asking widget.
  static ValueListenable<int> get activeTransitions => _activeTransitions;

  /// True when a route transition is animating in a navigator that is an
  /// ANCESTOR of [context] — i.e. one whose slide actually moves the asking
  /// widget. A push inside one tab's nested router is NOT in the root tab
  /// bar's scope (only that tab's content slides); a root-navigator push is
  /// (the whole screen, tab bar included, slides). Mirrors the `_mountDepth`
  /// baseline pattern `AppBoxKitNativeChromeGate` already uses for modal
  /// depth: a scoped signal, never a raw global.
  static bool hasActiveTransitionAbove(BuildContext context) {
    if (_activeTransitions.value <= 0) return false;
    // Lazy prune: drained instances whose navigator detached are defunct.
    _instances
        .removeWhere((o) => o._transitionCount <= 0 && o.navigator == null);
    // The navigators enclosing [context], innermost to root.
    final Set<NavigatorState> ancestors = <NavigatorState>{};
    NavigatorState? nav = Navigator.maybeOf(context);
    while (nav != null) {
      ancestors.add(nav);
      nav = Navigator.maybeOf(nav.context);
    }
    for (final CNTransitionObserver observer in _instances) {
      if (observer._transitionCount <= 0) continue;
      final NavigatorState? scope = observer.navigator;
      // A transitioning observer detached from its navigator mid-flight can't
      // prove its scope — hide conservatively until its watchdog drains it.
      if (scope == null || ancestors.contains(scope)) return true;
    }
    return false;
  }

  /// Test hook: clears static transition state that would otherwise leak
  /// across `testWidgets` zones (each test's FakeAsync discards the pending
  /// end/watchdog timers, stranding the counters mid-transition).
  @visibleForTesting
  static void resetForTesting() {
    _activeTransitions.value = 0;
    for (final CNTransitionObserver observer in _instances) {
      observer._transitionCount = 0;
    }
    _instances.clear();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _beginTransition();
    _scheduleEndTransition(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _beginTransition();
    _scheduleEndTransition(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _beginTransition();
    _scheduleEndTransition(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _beginTransition();
    _scheduleEndTransition(previousRoute);
  }

  // Interactive back-swipe (iOS edge-drag): the pop's `didPop` fires only at
  // COMMIT, so the drag itself is otherwise unguarded — the exact window the
  // app-bar glass leaked in. Hold the transition open for the whole gesture
  // (a cancelled swipe's `didStopUserGesture` balances the `didStartUserGesture`
  // begin; a committed one is carried past the gesture by `didPop`'s scheduled
  // end, so the flag stays set through the settle animation).
  @override
  void didStartUserGesture(
      Route<dynamic> route, Route<dynamic>? previousRoute) {
    _beginTransition();
  }

  @override
  void didStopUserGesture() {
    _endTransition();
  }

  void _beginTransition() {
    _transitionCount++;
    _activeTransitions.value = _activeTransitions.value + 1;
    // The native begin/endTransition calls only have an iOS implementation
    // (Liquid Glass tint); on Android/macOS the method channel has no handler
    // and the call throws MissingPluginException into the zone error handler.
    // Guard so the noise stops at the source. The Dart-side
    // [_activeTransitions] signal still drives AppBoxKitNativeChromeGate everywhere.
    if (_transitionCount == 1 && (!kIsWeb && Platform.isIOS)) {
      CupertinoNativePlatform.instance.beginTransition();
    }
  }

  void _scheduleEndTransition(Route<dynamic>? route) {
    // Get the animation from the route (only ModalRoute has animation)
    Animation<double>? animation;
    ModalRoute<dynamic>? modalRoute;
    if (route is ModalRoute) {
      modalRoute = route;
      animation = route.animation;
    }

    if (animation != null && animation.status != AnimationStatus.completed) {
      // End exactly once per scheduled transition, no matter which of the
      // listener / watchdog paths fires first.
      bool ended = false;
      void end() {
        if (ended) return;
        ended = true;
        _endTransition();
      }

      // Wait for animation to complete
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          // ModalRoute.animation is a ProxyAnimation. During the push frame
          // HeroController sets route.offstage = true to measure hero
          // destinations, which swaps the proxy's parent to
          // kAlwaysCompleteAnimation and emits a spurious synchronous
          // `completed` notification (routes.dart, ModalRoute.offstage
          // setter). Treating that as the transition end collapses the
          // chrome-hide window to ~0ms on every push, so native Liquid Glass
          // views ghost through route transitions. Ignore terminal statuses
          // reported while the route is offstage — the proxy notifies again
          // with the real status when offstage flips back.
          if (modalRoute != null && modalRoute.offstage) {
            return;
          }
          animation!.removeStatusListener(listener);
          end();
        }
      }

      animation.addStatusListener(listener);

      // Watchdog: if the route is disposed mid-flight (navigator swap,
      // popUntil, tab-host rebuild) the terminal status never arrives and
      // the counter would stay pinned > 0, hiding chrome forever. `end` is
      // idempotent, so a late real notification stays balanced.
      final Duration budget =
          (route is TransitionRoute<dynamic>
              ? route.transitionDuration
              : Duration.zero) +
          const Duration(milliseconds: 1000);
      Future<void>.delayed(budget, () {
        if (ended) return;
        animation!.removeStatusListener(listener);
        end();
      });
    } else {
      // No animation or already complete, end after a short delay
      Future.delayed(const Duration(milliseconds: 350), _endTransition);
    }
  }

  void _endTransition() {
    _transitionCount--;
    final int next = _activeTransitions.value - 1;
    _activeTransitions.value = next < 0 ? 0 : next;
    if (_transitionCount <= 0) {
      _transitionCount = 0;
      // Mirror the begin guard — only iOS has a native handler.
      if (!kIsWeb && Platform.isIOS) {
        CupertinoNativePlatform.instance.endTransition();
      }
    }
  }
}

/// Static utility methods for manual transition control.
///
/// Use these when you need fine-grained control over transition notifications,
/// such as with custom transitions or modal presentations.
class CNTransitionHelper {
  CNTransitionHelper._();

  /// Call this before starting a navigation transition.
  static Future<void> beginTransition() {
    return CupertinoNativePlatform.instance.beginTransition();
  }

  /// Call this after a navigation transition completes.
  static Future<void> endTransition() {
    return CupertinoNativePlatform.instance.endTransition();
  }

  /// Wraps an async navigation operation with transition notifications.
  ///
  /// Example:
  /// ```dart
  /// await CNTransitionHelper.withTransition(() async {
  ///   await Navigator.of(context).pushNamed('/details');
  /// });
  /// ```
  static Future<T> withTransition<T>(Future<T> Function() operation) async {
    await beginTransition();
    try {
      return await operation();
    } finally {
      // Delay end to allow animation to complete
      Future.delayed(const Duration(milliseconds: 350), endTransition);
    }
  }
}
