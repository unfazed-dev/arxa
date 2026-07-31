import 'package:flutter/material.dart';

import 'kit_motion_spec.dart';

/// Establishes the motion *driver* for a subtree: the single 0→1
/// [Animation] every descendant [KitWake] slices its stagger window from.
///
/// - **Route-driven (default):** with [driver] null, the enclosing
///   [ModalRoute]'s animation is used. Children wake as the route pushes and
///   scrub back down as it pops — including interactive swipe-back, where
///   the set-down tracks the user's finger for free.
/// - **Explicit driver:** pass any [Animation] — a
///   [KitDirectionalTabTransition]-style tab animation, a scroll-mapped
///   animation, or a manual [AnimationController] the caller replays
///   (`controller.forward(from: 0)` re-wakes, `controller.reverse()`
///   sets down).
///
/// With no scope in context, [KitWake] renders children untouched, so
/// shared kit components stay safe to embed anywhere.
class KitMotionScope extends StatefulWidget {
  const KitMotionScope({
    super.key,
    this.driver,
    this.spec,
    required this.child,
  });

  /// The 0→1 timeline to choreograph against. Defaults to the enclosing
  /// route's animation; falls back to [kAlwaysCompleteAnimation] (children
  /// render settled) when neither is available.
  final Animation<double>? driver;

  /// Scope-level spec override. Defaults to the [KitMotionSpec] theme
  /// extension (else [KitMotionSpec.standard]).
  final KitMotionSpec? spec;

  final Widget child;

  /// The nearest scope's state, or null when none is above [context].
  static KitMotionScopeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_KitMotionInherited>()
      ?.state;

  @override
  State<KitMotionScope> createState() => KitMotionScopeState();
}

class KitMotionScopeState extends State<KitMotionScope> {
  int _nextOrder = 0;
  Animation<double>? _routeAnimation;

  /// The resolved driver animation for this scope.
  Animation<double> get driver =>
      widget.driver ?? _routeAnimation ?? kAlwaysCompleteAnimation;

  /// The resolved spec for a descendant at [context].
  KitMotionSpec specOf(BuildContext context) =>
      widget.spec ?? KitMotionSpec.of(context);

  /// Claims the next auto-stagger slot. Called once per [KitWake] (in build
  /// order) when no explicit `order` was given; the claim is sticky for the
  /// lifetime of that widget's state so rebuilds never reshuffle slots.
  int claimOrder() => _nextOrder++;

  /// A 0→1 animation covering stagger slot [order]'s eased slice of the
  /// driver timeline. Scrubs in reverse with the driver (set-down). Callers
  /// own disposal when the returned animation is a [CurvedAnimation].
  CurvedAnimation slice(int order, KitMotionSpec spec) =>
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

  final KitMotionScopeState state;
  final Animation<double> driver;
  final KitMotionSpec? spec;

  @override
  bool updateShouldNotify(_KitMotionInherited oldWidget) =>
      driver != oldWidget.driver || spec != oldWidget.spec;
}
