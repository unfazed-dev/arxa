import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'appbox_kit_motion_scope.dart';
import 'appbox_kit_motion_spec.dart';

/// Bridges a [AppBoxKitMotionScope] slice into a flutter_animate [Animate]
/// timeline, so *any* effect from the flutter_animate catalogue rides the
/// same route/tab/manual driver as the pure-transition [AppBoxKitWake] widgets —
/// including reverse scrubbing during set-down:
///
/// ```dart
/// Builder(builder: (context) {
///   return card
///       .animate(adapter: AppBoxKitMotionAdapter.of(context))
///       .fadeIn()
///       .blurXY(begin: 8, end: 0);
/// });
/// ```
class AppBoxKitMotionAdapter extends Adapter {
  /// Drives an [Animate] timeline from an explicit 0→1 [animation].
  AppBoxKitMotionAdapter(this.animation, {super.animated, super.direction});

  /// Drives an [Animate] timeline from the enclosing scope's next (or
  /// [order]'s) stagger slice. Falls back to a completed animation when no
  /// scope is above [context], mirroring [AppBoxKitWake]'s safe degrade.
  factory AppBoxKitMotionAdapter.of(
    BuildContext context, {
    int? order,
    AppBoxKitMotionSpec? spec,
    bool? animated,
    Direction? direction,
  }) {
    final scope = AppBoxKitMotionScope.maybeOf(context);
    if (scope == null) {
      return AppBoxKitMotionAdapter(kAlwaysCompleteAnimation,
          animated: animated, direction: direction);
    }
    final resolvedSpec = spec ?? scope.specOf(context);
    final resolvedOrder = order ?? scope.claimOrder();
    return AppBoxKitMotionAdapter(
      scope.slice(resolvedOrder, resolvedSpec),
      animated: animated,
      direction: direction,
    );
  }

  /// The 0→1 source animation (already sliced/eased by the scope when
  /// constructed via [AppBoxKitMotionAdapter.of]).
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
