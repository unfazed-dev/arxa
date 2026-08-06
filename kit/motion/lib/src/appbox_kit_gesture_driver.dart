import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

import 'appbox_kit_springs.dart';

/// A gesture-driven 0→1 driver for `AppBoxKitMotionScope`: drag input scrubs the
/// timeline, release settles it to an end state with a spring. It IS the
/// `Animation<double>` the scope's explicit-driver contract consumes —
/// hand it straight over:
///
/// ```dart
/// final driver = AppBoxKitGestureDriver(vsync: this);
/// AppBoxKitMotionScope(driver: driver, child: drawerBody);
/// ```
///
/// Drawer recipe (the primary consumer): a horizontal drag across `extent`
/// pixels maps to the full 0→1 open progress —
///
/// ```dart
/// GestureDetector(
///   onHorizontalDragUpdate: (d) => driver.scrubBy(d.primaryDelta! / extent),
///   onHorizontalDragEnd: (d) => driver.settle(velocity: d.primaryVelocity! / extent),
/// )
/// ```
///
/// Progress-domain only (no pixels, no gesture arena) — callers map their
/// own drag geometry, so end drawers just negate the deltas.
class AppBoxKitGestureDriver extends AnimationController {
  AppBoxKitGestureDriver({
    required super.vsync,
    double initialValue = 0.0,
    this.settleSpring = AppBoxKitSprings.snappy,
    this.completionThreshold = 0.5,
    super.debugLabel,
  }) : super(value: initialValue);

  /// The spring [settle] lands with; presets live in [AppBoxKitSprings]. Mutable
  /// so a surface can re-tune without rebuilding the scope.
  SpringDescription settleSpring;

  /// Fallback for a near-stationary release: positions at or above this
  /// fraction settle to 1 (open), below it to 0 (closed).
  double completionThreshold;

  /// Scrub to [progress] (clamped to 0→1), cancelling any in-flight settle —
  /// re-grabbing mid-settle just works.
  void scrubTo(double progress) {
    stop();
    value = progress.clamp(0.0, 1.0);
  }

  /// Scrub by [deltaFraction] of the full 0→1 range.
  void scrubBy(double deltaFraction) => scrubTo(value + deltaFraction);

  /// Settle with [settleSpring], carrying the release [velocity]
  /// (fraction/second) so flings feel continuous. An explicit [to] wins;
  /// otherwise the velocity sign decides, with [completionThreshold] as the
  /// tiebreak for a near-stationary release.
  TickerFuture settle({double? to, double velocity = 0.0}) {
    final target = to ??
        (velocity.abs() > 0.05
            ? (velocity > 0 ? 1.0 : 0.0)
            : (value >= completionThreshold ? 1.0 : 0.0));
    return animateWith(
      SpringSimulation(settleSpring, value, target, velocity),
    );
  }
}
