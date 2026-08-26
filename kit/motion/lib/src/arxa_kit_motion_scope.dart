import 'package:flutter/material.dart';

import 'arxa_kit_motion_spec.dart';

/// Establishes the motion *driver* for a subtree: the single 0→1
/// [Animation] every descendant [ArxaKitWake] slices its stagger window from.
///
/// - **Route-driven (default):** with [driver] null, the enclosing
///   [ModalRoute]'s animation is used. Children wake as the route pushes and
///   scrub back down as it pops — including interactive swipe-back, where
///   the set-down tracks the user's finger for free.
/// - **Explicit driver:** pass any [Animation] — a
///   [ArxaKitDirectionalTabTransition]-style tab animation, a scroll-mapped
///   animation, or a manual [AnimationController] the caller replays
///   (`controller.forward(from: 0)` re-wakes, `controller.reverse()`
///   sets down).
///
/// With no scope in context, [ArxaKitWake] renders children untouched, so
/// shared kit components stay safe to embed anywhere.
class ArxaKitMotionScope extends StatefulWidget {
  const ArxaKitMotionScope({
    super.key,
    this.driver,
    this.spec,
    required this.child,
  });

  /// The 0→1 timeline to choreograph against. Defaults to the enclosing
  /// route's animation; falls back to [kAlwaysCompleteAnimation] (children
  /// render settled) when neither is available.
  final Animation<double>? driver;

  /// Scope-level spec override. Defaults to the [ArxaKitMotionSpec] theme
  /// extension (else [ArxaKitMotionSpec.standard]).
  final ArxaKitMotionSpec? spec;

  final Widget child;

  /// The nearest scope's state, or null when none is above [context].
  static ArxaKitMotionScopeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_KitMotionInherited>()
      ?.state;

  @override
  State<ArxaKitMotionScope> createState() => ArxaKitMotionScopeState();
}

class ArxaKitMotionScopeState extends State<ArxaKitMotionScope> {
  int _nextOrder = 0;
  Animation<double>? _routeAnimation;

  /// The resolved driver animation for this scope.
  Animation<double> get driver =>
      widget.driver ?? _routeAnimation ?? kAlwaysCompleteAnimation;

  /// The resolved spec for a descendant at [context].
  ArxaKitMotionSpec specOf(BuildContext context) =>
      widget.spec ?? ArxaKitMotionSpec.of(context);

  /// Claims the next auto-stagger slot. Called once per [ArxaKitWake] (in build
  /// order) when no explicit `order` was given; the claim is sticky for the
  /// lifetime of that widget's state so rebuilds never reshuffle slots.
  int claimOrder() => _nextOrder++;

  /// A 0→1 animation covering stagger slot [order]'s eased slice of the
  /// driver timeline. Scrubs in reverse with the driver (set-down). Callers
  /// own disposal when the returned animation is a [CurvedAnimation].
  CurvedAnimation slice(int order, ArxaKitMotionSpec spec) =>
      CurvedAnimation(parent: driver, curve: spec.intervalFor(order));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeAnimation = ModalRoute.of(context)?.animation;
  }

  @override
  Widget build(BuildContext context) {
    return _KitMotionInherited(
      state: this,
      driver: driver,
      spec: widget.spec,
      child: widget.child,
    );
  }
}

class _KitMotionInherited extends InheritedWidget {
  const _KitMotionInherited({
    required this.state,
    required this.driver,
    required this.spec,
    required super.child,
  });

  final ArxaKitMotionScopeState state;
  final Animation<double> driver;
  final ArxaKitMotionSpec? spec;

  @override
  bool updateShouldNotify(_KitMotionInherited oldWidget) =>
      driver != oldWidget.driver || spec != oldWidget.spec;
}
