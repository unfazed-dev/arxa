import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'kit_motion_scope.dart';
import 'kit_motion_spec.dart';

/// Bridges a [KitMotionScope] slice into a flutter_animate [Animate]
/// timeline, so *any* effect from the flutter_animate catalogue rides the
/// same route/tab/manual driver as the pure-transition [KitWake] widgets —
/// including reverse scrubbing during set-down:
///
/// ```dart
/// Builder(builder: (context) {
///   return card
///       .animate(adapter: KitMotionAdapter.of(context))
///       .fadeIn()
///       .blurXY(begin: 8, end: 0);
/// });
/// ```
class KitMotionAdapter extends Adapter {
  /// Drives an [Animate] timeline from an explicit 0→1 [animation].
  KitMotionAdapter(this.animation, {super.animated, super.direction});

  /// Drives an [Animate] timeline from the enclosing scope's next (or
  /// [order]'s) stagger slice. Falls back to a completed animation when no
  /// scope is above [context], mirroring [KitWake]'s safe degrade.
  factory KitMotionAdapter.of(
    BuildContext context, {
    int? order,
    KitMotionSpec? spec,
    bool? animated,
    Direction? direction,
  }) {
    final scope = KitMotionScope.maybeOf(context);
    if (scope == null) {
      return KitMotionAdapter(kAlwaysCompleteAnimation,
          animated: animated, direction: direction);
    }
    final resolvedSpec = spec ?? scope.specOf(context);
    final resolvedOrder = order ?? scope.claimOrder();
    return KitMotionAdapter(
      scope.slice(resolvedOrder, resolvedSpec),
      animated: animated,
      direction: direction,
    );
  }

  /// The 0→1 source animation (already sliced/eased by the scope when
  /// constructed via [KitMotionAdapter.of]).
  final Animation<double> animation;

  VoidCallback? _listener;

  @override
  void attach(AnimationController controller) {
    config(controller, animation.value.clamp(0.0, 1.0));
    animation.addListener(
      _listener = () => updateValue(animation.value.clamp(0.0, 1.0)),
    );
  }

  @override
  void detach() {
    if (_listener != null) {
      animation.removeListener(_listener!);
      _listener = null;
    }
    super.detach();
  }
}
