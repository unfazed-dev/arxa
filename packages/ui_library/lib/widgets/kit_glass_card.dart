import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNGlassEffect,
        CNGlassEffectShape,
        LiquidGlassConfig,
        LiquidGlassContainer;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/platform/kit_platform.dart';

import 'kit_frosted_surface.dart';
import 'kit_native_chrome_gate.dart';

/// Adaptive glass / card surface — two render paths (ADR 0010 tier split):
/// - **iOS 26 native** — delegates to `cupertino_native_better`'s
///   [LiquidGlassContainer], which paints real Liquid Glass over [child] (a
///   native UIView via hybrid composition). Gated on
///   [KitPlatform.supportsLiquidGlass]; below iOS 26 the container degrades to
///   a bare child (no card chrome), so the kit falls through to the frosted
///   tier there — mirrors [KitNativeTabBar]'s glass gate.
/// - **Flutter-drawn frosted** — [KitFrostedSurface] (BackdropFilter blur +
///   saturation + theme tint + rim highlight) everywhere else: Android,
///   desktop, web, iOS < 26, and any host that passes `wantNative: false`.
///   Per Apple's own guidance, content-layer surfaces use standard materials,
///   not Liquid Glass — and the Flutter-drawn tier is occlusion-safe by
///   construction (it scrolls, clips, and animates without a platform view
///   to bleed or leak).
///
/// The public surface is **primitives only** ([child], [padding],
/// [borderRadius], [wantNative]) so hosts never import either underlying dep.
/// [wantNative] is the host opt-in: set it `false` to force the frosted
/// tier on a platform that would otherwise render native glass.
class KitGlassCard extends StatelessWidget {
  const KitGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.wantNative = true,
  });

  /// The card content.
  final Widget child;

  /// Inner padding around [child], applied on every tier. Defaults to 16dp on
  /// all sides so content never touches the card edge (the glass tier paints
  /// flush to its bounds); pass [EdgeInsets.zero] for a full-bleed child.
  final EdgeInsets? padding;

  /// Corner radius. On the glass tier this maps to
  /// [LiquidGlassConfig.cornerRadius] (rect shape); on the frosted tier it
  /// maps to [KitFrostedSurface.borderRadius]. `null` = 16 dp on both tiers
  /// (a card is always rect-shaped, never the capsule default).
  final double? borderRadius;

  /// Host opt-in to native chrome. `true` (default) renders Liquid Glass on
  /// iOS 26; `false` forces the Flutter-drawn frosted tier everywhere.
  final bool wantNative;

  @override
  Widget build(BuildContext context) {
    final content =
        padding == null ? child : Padding(padding: padding!, child: child);

    // Tier 1 — iOS 26 Liquid Glass.
    if (wantNative && KitPlatform.supportsLiquidGlass) {
      return LiquidGlassContainer(
        config: LiquidGlassConfig(
          // A card is rect-shaped, not a capsule — LiquidGlassConfig honors
          // cornerRadius only in rect mode.
          shape: CNGlassEffectShape.rect,
          cornerRadius: borderRadius ?? 16,
          effect: CNGlassEffect.regular,
        ),
        child: content,
      ).chromeGated();
    }
    // Tier 2 — Flutter-drawn frosted (Android / fallback / wantNative: false).
    // One path on purpose: ADR 0010 makes the frosted material the correct
    // content-layer surface on EVERY non-iOS-26 tier, and unlike the old
    // Material Card it can't desync visually from the iOS glass tier.
    return KitFrostedSurface(
      borderRadius: borderRadius ?? 16,
      child: content,
    );
  }
}
