import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
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

  /// Set once this observer has been seen attached to a [Navigator]. Guards the
  /// lazy prune in [hasActiveTransitionAbove]: a freshly constructed observer
  /// is registered BEFORE the navigator adopts it, and looks identical to a
  /// defunct one (`navigator == null`, count 0). Pruning it there would drop it
  /// permanently — nothing re-registers — and hosts build observers from a
  /// closure (`navigatorObservers: () => [CNTransitionObserver()]`), so that
  /// window is hit on every router rebuild.
  bool _wasAttached = false;

  /// Every constructed observer — one per navigator that registered one (root
  /// plus each nested router). [NavigatorObserver] has no dispose hook, so
  /// defunct instances are pruned lazily in [hasActiveTransitionAbove] once
  /// they have drained AND their navigator has detached.
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
  /// navigator, root or nested. Use it as a *change signal* (it ticks on every
  /// begin and end, so listeners get told to re-evaluate); for the actual
  /// hide decision use [hasActiveTransitionAbove], which scopes the answer to
  /// the navigators that can actually move the asking widget.
  static ValueListenable<int> get activeTransitions => _activeTransitions;

  /// True when a route transition is animating in a navigator that ENCLOSES
  /// [context] — i.e. one whose slide actually carries the asking widget.
  ///
  /// A push inside one tab's nested router is NOT in the root tab bar's scope
  /// (only that tab's content slides), whereas a root-navigator push is (the
  /// whole screen, tab bar included, slides). Reading the raw global
  /// [activeTransitions] instead made any nested push dematerialize the root
  /// chrome across every tab — fix C2 of
  /// `docs/plans/glass-chrome-root-cause-fixes.md`. This mirrors the
  /// `_mountDepth` baseline that `AppBoxKitNativeChromeGate` already applies to
  /// modal depth: a scoped signal, never a raw global.
  static bool hasActiveTransitionAbove(BuildContext context) {
    if (_activeTransitions.value <= 0) return false;

    // Lazy prune (see [_wasAttached]): an observer that has drained and whose
    // navigator has detached can never speak again.
    _instances.removeWhere((CNTransitionObserver observer) {
      if (observer.navigator != null) {
        observer._wasAttached = true;
        return false;
      }
      return observer._wasAttached && observer._transitionCount <= 0;
    });

    // Navigators enclosing [context], innermost outwards. `nav.context` is the
    // Navigator's own element, so walk from its PARENT — `Navigator.maybeOf`
    // would hand back the same state and spin forever.
    final Set<NavigatorState> enclosing = <NavigatorState>{};
    NavigatorState? nav = Navigator.maybeOf(context);
    while (nav != null) {
      enclosing.add(nav);
      nav = nav.context.findAncestorStateOfType<NavigatorState>();
    }

    for (final CNTransitionObserver observer in _instances) {
      if (observer._transitionCount <= 0) continue;
      final NavigatorState? scope = observer.navigator;
      // A transitioning observer that has detached mid-flight can no longer
      // prove its scope (navigator swap, tab-host rebuild). Hide
      // conservatively until its watchdog drains the count.
      if (scope == null || enclosing.contains(scope)) return true;
    }
    return false;
  }

  /// Test hook: clears the static transition state that would otherwise leak
  /// between `testWidgets` zones — each test's FakeAsync discards the pending
  /// end/watchdog timers, stranding counters mid-transition.
  @visibleForTesting
  static void resetForTesting() {
    _activeTransitions.value = 0;
    for (final CNTransitionObserver observer in _instances) {
      observer._transitionCount = 0;
      observer._gestureTransitionActive = false;
    }
    _instances.clear();
  }

  /// Only OPAQUE transition routes drive the chrome hide.
  ///
  /// The hide exists for one reason: a hybrid-composition platform view cannot
  /// slide with a full-screen route, so it must leave the frame while a page
  /// covers the screen. A non-opaque route (dialog, `showCupertinoModalPopup`,
  /// `CupertinoSheetRoute`, bottom sheet — all `opaque: false`) never covers
  /// the screen: the previous route stays live and visible for the modal's
  /// whole lifetime. Hiding chrome there IS the user-visible bug — native
  /// glass blinks out on open and re-materializes on close.
  static bool _drivesChromeHide(Route<dynamic>? route) =>
      route is TransitionRoute<dynamic> && route.opaque;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_drivesChromeHide(route)) return;
    _beginTransition();
    _scheduleEndTransition(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Same opacity rule as didPush: dismissing a translucent modal never
    // un-covers the screen (it was never covered), so there is nothing for
    // native chrome to collide with.
    if (!_drivesChromeHide(route)) return;
    _beginTransition();
    // Time the end against the route that is actually ANIMATING, which on a pop
    // is the OUTGOING `route` (its controller runs 1→0 to `dismissed`) — not
    // `previousRoute`.
    //
    // `previousRoute` is the one being revealed, and its own animation settled
    // at 1.0 back when it was pushed, so `status == completed` sent every pop
    // down the "no animation" fallback below: a blind 350ms timer. Cupertino's
    // slide is 500ms (`CupertinoRouteTransitionMixin.kTransitionDuration`), so
    // the hide window closed ~150ms before the page stopped moving and native
    // glass was restored on top of content still in flight.
    //
    // `didPush` already schedules on its animating route; this is the same rule,
    // and it makes the window track the real duration instead of a constant.
    _scheduleEndTransition(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // The incoming route is the one that animates (and the one that could
    // cover the screen); gate on it.
    if (!_drivesChromeHide(newRoute)) return;
    _beginTransition();
    _scheduleEndTransition(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Removing a translucent route uncovers nothing — skip, same rule.
    if (!_drivesChromeHide(route)) return;
    _beginTransition();
    // Intentionally still `previousRoute`, unlike didPop above: a remove is not
    // animated, so there is no in-flight animation to track and this lands on
    // the short fallback either way. Left alone on purpose — not an oversight.
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
    // A back-swipe on a translucent route drags content the previous page is
    // already visible under — same opacity rule. The flag below keeps the
    // unconditional `didStopUserGesture` from decrementing a begin that never
    // happened (the counter must never latch negative).
    if (!_drivesChromeHide(route)) return;
    _gestureTransitionActive = true;
    _beginTransition();
  }

  @override
  void didStopUserGesture() {
    if (!_gestureTransitionActive) return;
    _gestureTransitionActive = false;
    _endTransition();
  }

  /// Whether the current user gesture was counted by [didStartUserGesture].
  /// A [NavigatorObserver] is attached to exactly one navigator, and a
  /// navigator runs at most one route gesture at a time, so a bool suffices.
  bool _gestureTransitionActive = false;

  void _beginTransition() {
    _transitionCount++;
    _activeTransitions.value = _activeTransitions.value + 1;
    // The native `beginTransition`/`endTransition` pair is DELIBERATELY not
    // called any more. See [_endTransition] for the full reasoning; in short it
    // is a second, weaker hide authority whose only remaining effect was to make
    // glass re-materialize in the user's face on the way back from a route.
  }

  void _scheduleEndTransition(Route<dynamic>? route) {
    // Get the animation from the route (only ModalRoute has animation)
    Animation<double>? animation;
    ModalRoute<dynamic>? modalRoute;
    if (route is ModalRoute) {
      modalRoute = route;
      animation = route.animation;
    }

    // `dismissed` counts as settled alongside `completed`: a zero-duration route
    // handed to didPop is ALREADY dismissed, and treating that as in-flight
    // would attach a listener nothing will ever fire, leaving the watchdog
    // (transitionDuration + 1000ms) to hide chrome for a full second after an
    // instant pop. Both terminal statuses take the short fallback instead.
    if (animation != null &&
        animation.status != AnimationStatus.completed &&
        animation.status != AnimationStatus.dismissed) {
      // End exactly once per scheduled transition, no matter which of the
      // listener / disposal paths fires first.
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

      // Disposal guard: if the route is disposed mid-flight (navigator swap,
      // popUntil, tab-host rebuild) the terminal status never arrives and
      // the counter would stay pinned > 0, hiding chrome forever.
      // `TransitionRoute.dispose()` completes `_transitionCompleter`
      // unconditionally (routes.dart), so `route.completed` fires in exactly
      // that case — no wall-clock Timer needed. (The old watchdog Timer
      // stayed pending through widget-test teardown and tripped
      // `!timersPending` in every test that ends mid-transition on purpose.)
      // `end` is idempotent, so a late real notification stays balanced.
      if (route is TransitionRoute<dynamic>) {
        final Animation<double> watched = animation;
        route.completed.whenComplete(() {
          if (ended) return;
          watched.removeStatusListener(listener);
          end();
        });
      }
    } else {
      // No animation to watch means there is no visual transition to wait
      // out — end synchronously. The old 350ms wall-clock guess held the
      // chrome gate closed for a third of a second with nothing on screen
      // animating, and its pending Timer tripped `!timersPending` in widget
      // tests. The animation status is the one authority for "transition
      // running"; when it is absent, the transition is already over.
      _endTransition();
    }
  }

  /// SINGLE HIDE AUTHORITY — the native transition flag is not driven from here.
  ///
  /// `CupertinoNativePlatform.beginTransition()` / `endTransition()` set
  /// `CNTransitionObserver.shared.isTransitioning` on the iOS side, and its only
  /// consumers are three views that swap their glass for a flat fill while it is
  /// true — e.g. `LiquidGlassContainerView.swift:280`:
  ///
  /// ```swift
  /// if isTransitioning { self.background(shape.fill(...)) }
  /// else               { self.glassEffect(glass, in: shape) }
  /// ```
  ///
  /// That is a `@ViewBuilder` if/else, so the two arms are structurally distinct
  /// views. Flipping the flag back tears one down and inserts the other, which
  /// applies `.glassEffect` *afresh* — and establishing glass materializes with
  /// an animation by Apple's design (WWDC25 #284). On a push nobody sees it: the
  /// flag clears while the route is still covered. On a POP it clears exactly as
  /// the revealed route becomes visible, so the user watches every glass surface
  /// animate itself back in. That is the reported bug.
  ///
  /// De-tinting was never sufficient anyway, which this file already said above:
  /// a hybrid-composition platform view *cannot be tinted out of a leak* — it has
  /// to leave the frame's layer tree, and `AppBoxKitNativeChromeGate` is what
  /// actually does that. So the native flag is a second authority that duplicates
  /// a job it cannot do, at the cost of an animation. Same call as C5 in
  /// `appbox_kit_tab_bar.dart`: one authority per event, and it is the gate.
  ///
  /// Per-view `setTransitioning` (Issue #29 halo containment) is a SEPARATE
  /// channel call on each view's own channel and is untouched by this.
  void _endTransition() {
    _transitionCount--;
    final int next = _activeTransitions.value - 1;
    _activeTransitions.value = next < 0 ? 0 : next;
    if (_transitionCount <= 0) {
      _transitionCount = 0;
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
