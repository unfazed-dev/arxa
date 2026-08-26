import 'package:flutter/physics.dart';

/// Spring presets for gesture-settle motion — the drawer/sheet-style
/// "release and it lands" feel. Mirrors the [ArxaKitMotionSpec] preset
/// vocabulary (`standard` / `subtle` / `energetic`): static const fields on
/// a non-instantiable holder, consumed by `ArxaKitGestureDriver.settleSpring`.
///
/// All presets are raw [SpringDescription]s — const-constructible, unlike
/// `SpringDescription.withDampingRatio` (which computes with `sqrt`). The
/// damping ratio ζ each encodes is noted in its doc comment.
abstract final class ArxaKitSprings {
  /// Default drawer settle — critically damped (ζ = 1.0), lands in ~0.3 s
  /// with no overshoot. The `ArxaKitGestureDriver` default.
  static const SpringDescription snappy =
      SpringDescription(mass: 1, stiffness: 256, damping: 32);

  /// Large-surface settle (sheets) — critically damped (ζ = 1.0) but slower
  /// (~0.5 s), so full-height panels don't slam home.
  static const SpringDescription gentle =
      SpringDescription(mass: 1, stiffness: 100, damping: 20);

  /// Playful settle — underdamped (ζ ≈ 0.7), arrives faster with a lively
  /// feel. Note the 0→1 driver clamps at its bounds, so the overshoot reads
  /// as extra snap rather than a bounce past the end state.
  static const SpringDescription bouncy =
      SpringDescription(mass: 1, stiffness: 300, damping: 24);
}
