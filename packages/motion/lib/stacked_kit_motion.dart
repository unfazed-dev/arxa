/// appbox_kit_motion — route-driven wake-up & set-down choreography.
///
/// Wrap a screen's body in a [KitMotionScope] (route animation is picked up
/// automatically), then mark children with [KitWake] / `.wake()`. Children
/// stagger in as the driver runs 0→1 and scrub back down as it reverses
/// (predictive back, swipe-to-pop, tab slide). Tune globally via the
/// [KitMotionSpec] theme extension.
library appbox_kit_motion;

export 'src/kit_gesture_driver.dart';
export 'src/kit_motion_adapter.dart';
export 'src/kit_motion_scope.dart';
export 'src/kit_motion_spec.dart';
export 'src/kit_springs.dart';
export 'src/kit_wake.dart';
export 'src/kit_wake_extension.dart';
