import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Tuning knobs for kit motion, registered as a [ThemeExtension] so an app
/// (or a subtree) can re-tune wake/set-down choreography without touching
/// call sites:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(extensions: const [AppBoxKitMotionSpec.subtle]),
/// )
/// ```
///
/// All timing values are expressed as *fractions of the driver timeline*
/// (usually the route transition), never absolute durations — the kit never
/// extends a route's transition; it choreographs within it.
@immutable
class AppBoxKitMotionSpec extends ThemeExtension<AppBoxKitMotionSpec> {
  const AppBoxKitMotionSpec({
    this.enabled = true,
    this.staggerFraction = 0.06,
    this.maxStartFraction = 0.5,
    this.curve = Curves.easeOutCubic,
    this.offset = const Offset(0, 0.08),
    this.fade = true,
    this.scale = 1.0,
  })  : assert(staggerFraction >= 0 && staggerFraction < 1,
            'staggerFraction must be in [0, 1)'),
        assert(maxStartFraction >= 0 && maxStartFraction < 1,
            'maxStartFraction must be in [0, 1) — every child must retain '
            'a non-empty slice of the driver timeline'),
        assert(scale > 0 && scale <= 1, 'scale must be in (0, 1]');

  /// Master switch. When `false`, [AppBoxKitWake] renders its child untouched.
  final bool enabled;

  /// How far into the driver timeline each successive stagger slot starts
  /// (slot `n` starts at `n * staggerFraction`).
  final double staggerFraction;

  /// Ceiling for stagger starts — the motion *budget*. No matter how many
  /// children wake, the last one still gets at least
  /// `1 - maxStartFraction` of the timeline to land before the route settles.
  final double maxStartFraction;

  /// Easing applied to each child's slice of the timeline.
  final Curve curve;

  /// Slide-in origin as a fraction of the child's own size
  /// (see [SlideTransition]). Horizontal components mirror under RTL.
  final Offset offset;

  /// Whether children fade in as they wake.
  final bool fade;

  /// Starting scale (1.0 disables the scale channel).
  final double scale;

  /// Default look: 8%-height rise + fade, ease-out-cubic.
  static const AppBoxKitMotionSpec standard = AppBoxKitMotionSpec();

  /// Quieter variant for dense/utility surfaces.
  static const AppBoxKitMotionSpec subtle = AppBoxKitMotionSpec(
    staggerFraction: 0.04,
    offset: Offset(0, 0.04),
  );

  /// Showier variant for marketing/hero surfaces.
  static const AppBoxKitMotionSpec energetic = AppBoxKitMotionSpec(
    staggerFraction: 0.09,
    offset: Offset(0, 0.12),
    scale: 0.96,
  );

  /// The active spec: nearest theme extension, else [standard].
  static AppBoxKitMotionSpec of(BuildContext context) =>
      Theme.of(context).extension<AppBoxKitMotionSpec>() ?? standard;

  /// Normalized timeline position at which stagger slot [order] begins.
  double startFor(int order) =>
      (order * staggerFraction).clamp(0.0, maxStartFraction);

  /// The eased sub-interval of the driver timeline for stagger slot [order].
  Curve intervalFor(int order) =>
      Interval(startFor(order), 1.0, curve: curve);

  @override
  AppBoxKitMotionSpec copyWith({
    bool? enabled,
    double? staggerFraction,
    double? maxStartFraction,
    Curve? curve,
    Offset? offset,
    bool? fade,
    double? scale,
  }) {
    return AppBoxKitMotionSpec(
      enabled: enabled ?? this.enabled,
      staggerFraction: staggerFraction ?? this.staggerFraction,
      maxStartFraction: maxStartFraction ?? this.maxStartFraction,
      curve: curve ?? this.curve,
      offset: offset ?? this.offset,
      fade: fade ?? this.fade,
      scale: scale ?? this.scale,
    );
  }

  @override
  AppBoxKitMotionSpec lerp(ThemeExtension<AppBoxKitMotionSpec>? other, double t) {
    if (other is! AppBoxKitMotionSpec) return this;
    return AppBoxKitMotionSpec(
      enabled: t < 0.5 ? enabled : other.enabled,
      staggerFraction:
          lerpDouble(staggerFraction, other.staggerFraction, t)!,
      maxStartFraction:
          lerpDouble(maxStartFraction, other.maxStartFraction, t)!,
      curve: t < 0.5 ? curve : other.curve,
      offset: Offset.lerp(offset, other.offset, t)!,
      fade: t < 0.5 ? fade : other.fade,
      scale: lerpDouble(scale, other.scale, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitMotionSpec &&
          other.enabled == enabled &&
          other.staggerFraction == staggerFraction &&
          other.maxStartFraction == maxStartFraction &&
          other.curve == curve &&
          other.offset == offset &&
          other.fade == fade &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(enabled, staggerFraction, maxStartFraction,
      curve, offset, fade, scale);
}
