/// arxa_kit_motion — route-driven wake-up & set-down choreography.
///
/// Wrap a screen's body in a [ArxaKitMotionScope] (route animation is picked up
/// automatically), then mark children with [ArxaKitWake] / `.wake()`. Children
/// stagger in as the driver runs 0→1 and scrub back down as it reverses
/// (predictive back, swipe-to-pop, tab slide). Tune globally via the
/// [ArxaKitMotionSpec] theme extension.
library arxa_kit_motion;

export 'src/arxa_kit_gesture_driver.dart';
export 'src/arxa_kit_motion_adapter.dart';
export 'src/arxa_kit_motion_scope.dart';
export 'src/arxa_kit_motion_spec.dart';
export 'src/arxa_kit_springs.dart';
export 'src/arxa_kit_wake.dart';
export 'src/arxa_kit_wake_extension.dart';
