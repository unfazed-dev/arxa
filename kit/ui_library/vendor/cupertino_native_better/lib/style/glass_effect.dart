import 'package:flutter/widgets.dart';
import '../utils/version_detector.dart';
import '../components/liquid_glass_container.dart';

/// Liquid Glass effect variants for iOS 26+.
enum CNGlassEffect {
  /// Regular glass effect with standard blur and transparency.
  regular,

  /// Prominent glass effect with enhanced visual prominence.
  prominent,

  /// LOCAL PATCH #10: no glass material at all — the shape is filled with
  /// [LiquidGlassConfig.tint] (or stays fully transparent when tint is null).
  /// Exists for Flutter-drawn chrome that floats over platform-view-bearing
  /// scrollables: the engine's view slicer (`flow/view_slicer.cc`) only keeps
  /// Flutter ops in an overlay above platform views while they intersect a
  /// platform-view rect, and drops them into the difference-clipped
  /// background canvas otherwise — a stationary `plain` container beneath
  /// such chrome guarantees the intersection every frame. Native side maps
  /// this to `Glass.identity` plus a plain SwiftUI fill, so no glass ever
  /// materializes and glass-on-glass stacking (clip 13-53) cannot occur.
  plain,
}

/// Shapes for Liquid Glass effects.
enum CNGlassEffectShape {
  /// Capsule shape (default) - rounded ends based on view height.
  capsule,

  /// Rectangle shape with specified corner radius.
  rect,

  /// Circle shape.
  circle,
}

/// LOCAL PATCH #11: elevation shadow spec for a LiquidGlassContainer.
///
/// Exists for Flutter-drawn chrome that rides a plain slicer anchor (toasts,
/// floating pills): the child must NOT paint its own `BoxShadow`, because a
/// shadow painted inside the anchored subtree spills past the child's layer
/// bounds and the engine's view slicer / the fade's opacity surface clip it
/// at the pill's rectangular bounding box — observed on-device (2026-08-15
/// clip) as a faint hard-edged rectangle where the soft shadow should be.
///
/// Declared here instead, on the container's config:
/// - **Native tier** — the shadow renders as a CALayer shadow on the
///   platform view itself (shadowPath matched to the configured shape),
///   composited by Core Animation outside every Flutter layer bound.
/// - **Fallback tier** — the container wraps its child with a
///   [ShapeDecoration] shadow matched to the configured shape, reproducing
///   exactly what the old in-decoration `BoxShadow` painted.
@immutable
class CNGlassShadow {
  /// Shadow color. Defaults to opaque black; [opacity] scales its alpha.
  final Color color;

  /// Shadow opacity 0..1 (multiplied into [color]'s alpha natively).
  final double opacity;

  /// Blur radius in logical pixels (maps 1:1 to CALayer.shadowRadius).
  final double radius;

  /// Shadow offset in logical pixels.
  final Offset offset;

  /// Creates a glass shadow with soft-black defaults (15% opacity, 16px
  /// blur, no offset) — pass [color]/[opacity]/[radius]/[offset] to tune.
  const CNGlassShadow({
    this.color = const Color(0xFF000000),
    this.opacity = 0.15,
    this.radius = 16,
    this.offset = Offset.zero,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CNGlassShadow &&
          color == other.color &&
          opacity == other.opacity &&
          radius == other.radius &&
          offset == other.offset;

  @override
  int get hashCode =>
      color.hashCode ^ opacity.hashCode ^ radius.hashCode ^ offset.hashCode;
}

/// Configuration for Liquid Glass effects.
class LiquidGlassConfig {
  /// The glass effect variant to apply.
  final CNGlassEffect effect;

  /// The shape for the glass effect.
  final CNGlassEffectShape shape;

  /// Corner radius for rectangle shape (only used when shape is rect).
  final double? cornerRadius;

  /// Optional tint color for the glass effect.
  final Color? tint;

  /// Whether the glass effect should be interactive (responds to touch/pointer).
  final bool interactive;

  /// LOCAL PATCH #11: optional elevation shadow — see [CNGlassShadow].
  ///
  /// Rendered natively (CALayer) on the glass tier and as a shape-matched
  /// ShapeDecoration on the fallback tier. The child should not paint its
  /// own shadow when this is set.
  final CNGlassShadow? shadow;

  /// Creates a configuration for Liquid Glass effects.
  const LiquidGlassConfig({
    this.effect = CNGlassEffect.regular,
    this.shape = CNGlassEffectShape.capsule,
    this.cornerRadius,
    this.tint,
    this.interactive = false,
    this.shadow,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassConfig &&
          runtimeType == other.runtimeType &&
          effect == other.effect &&
          shape == other.shape &&
          cornerRadius == other.cornerRadius &&
          tint == other.tint &&
          interactive == other.interactive &&
          shadow == other.shadow;

  @override
  int get hashCode =>
      effect.hashCode ^
      shape.hashCode ^
      (cornerRadius?.hashCode ?? 0) ^
      (tint?.hashCode ?? 0) ^
      interactive.hashCode ^
      (shadow?.hashCode ?? 0);
}

/// Extension on Widget to apply Liquid Glass effects.
///
/// Example usage:
/// ```dart
/// Text("Hello, World!")
///   .liquidGlass()
///
/// Text("Hello, World!")
///   .liquidGlass(
///     shape: CNGlassEffectShape.rect,
///     cornerRadius: 16.0,
///   )
///
/// Text("Hello, World!")
///   .liquidGlass(
///     effect: CNGlassEffect.regular,
///     tint: Colors.orange,
///     interactive: true,
///   )
/// ```
extension LiquidGlassExtension on Widget {
  /// Applies a Liquid Glass effect to this widget.
  ///
  /// On iOS 26+ and macOS 26+, this wraps the widget in a native container
  /// that applies the glass effect. On older versions or other platforms,
  /// the widget is returned unchanged.
  ///
  /// The [effect] determines the glass variant (regular or prominent).
  /// The [shape] determines the shape of the glass effect (capsule, rect, or circle).
  /// The [cornerRadius] is only used when [shape] is [CNGlassEffectShape.rect].
  /// The [tint] applies a color tint to the glass effect.
  /// The [interactive] makes the glass effect respond to touch/pointer interactions.
  Widget liquidGlass({
    CNGlassEffect effect = CNGlassEffect.regular,
    CNGlassEffectShape shape = CNGlassEffectShape.capsule,
    double? cornerRadius,
    Color? tint,
    bool interactive = false,
  }) {
    // Only apply glass effect on iOS 26+ or macOS 26+
    if (!PlatformVersion.supportsLiquidGlass) {
      return this;
    }

    return LiquidGlassContainer(
      config: LiquidGlassConfig(
        effect: effect,
        shape: shape,
        cornerRadius: cornerRadius,
        tint: tint,
        interactive: interactive,
      ),
      child: this,
    );
  }
}
