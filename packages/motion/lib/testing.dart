/// Test-facing helpers for appbox_kit_motion — deterministic drivers so
/// widget/golden tests can pin the choreography at any timeline position
/// without pumping real route transitions.
library appbox_kit_motion_testing;

import 'package:flutter/widgets.dart';

import 'appbox_kit_motion.dart';

/// A driver frozen at the settled end of the timeline — children render in
/// their final (fully woken) state. Ideal default for goldens.
const Animation<double> kitMotionSettled = AlwaysStoppedAnimation<double>(1.0);

/// A driver frozen at the start of the timeline — children render fully
/// set down (invisible when the spec fades).
const Animation<double> kitMotionDormant = AlwaysStoppedAnimation<double>(0.0);

/// Wraps [child] in a [KitMotionScope] frozen at timeline position [t]
/// (0 = dormant, 1 = settled).
Widget staticKitMotionScope({
  required Widget child,
  double t = 1.0,
  KitMotionSpec? spec,
}) {
  return KitMotionScope(
    driver: AlwaysStoppedAnimation<double>(t),
    spec: spec,
    child: child,
  );
}

/// Pins *gesture-driven* choreography: wraps [child] in a [KitMotionScope]
/// driven by a real [KitGestureDriver] parked at timeline position [t] with
/// no settle in flight — deterministic, golden-safe, and exercising the same
/// driver type the gesture path uses in production.
///
/// For behavioral tests that scrub/settle, construct the driver directly —
/// `WidgetTester` is a `TickerProvider`:
/// `KitGestureDriver(vsync: tester, initialValue: 0.4)`.
Widget gestureKitMotionScope({
  required Widget child,
  double t = 0.0,
  KitMotionSpec? spec,
  SpringDescription settleSpring = KitSprings.snappy,
}) {
  return _GestureKitMotionScope(
    t: t,
    spec: spec,
    settleSpring: settleSpring,
    child: child,
  );
}

class _GestureKitMotionScope extends StatefulWidget {
  const _GestureKitMotionScope({
    required this.t,
    required this.spec,
    required this.settleSpring,
    required this.child,
  });

  final double t;
  final KitMotionSpec? spec;
  final SpringDescription settleSpring;
  final Widget child;

  @override
  State<_GestureKitMotionScope> createState() => _GestureKitMotionScopeState();
}

class _GestureKitMotionScopeState extends State<_GestureKitMotionScope>
    with TickerProviderStateMixin {
  late KitGestureDriver _driver;

  @override
  void initState() {
    super.initState();
    _driver = KitGestureDriver(
      vsync: this,
      initialValue: widget.t,
      settleSpring: widget.settleSpring,
    );
  }

  @override
  void didUpdateWidget(_GestureKitMotionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.t != widget.t ||
        oldWidget.settleSpring != widget.settleSpring) {
      _driver.dispose();
      _driver = KitGestureDriver(
        vsync: this,
        initialValue: widget.t,
        settleSpring: widget.settleSpring,
      );
    }
  }

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KitMotionScope(
      driver: _driver,
      spec: widget.spec,
      child: widget.child,
    );
  }
}
