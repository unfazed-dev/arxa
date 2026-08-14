import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNGlassEffect,
        CNGlassEffectShape,
        LiquidGlassConfig,
        LiquidGlassContainer;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_frosted_surface.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive glass / card surface — two render paths (ADR 0010 tier split):
/// - **iOS 26 native** — delegates to `cupertino_native_better`'s
///   [LiquidGlassContainer], which paints real Liquid Glass over [child] (a
///   native UIView via hybrid composition). Gated on
///   [AppBoxKitPlatform.supportsLiquidGlass]; below iOS 26 the container degrades to
///   a bare child (no card chrome), so the kit falls through to the frosted
///   tier there — mirrors [AppBoxKitNativeTabBar]'s glass gate.
/// - **Flutter-drawn frosted** — [AppBoxKitFrostedSurface] (BackdropFilter blur +
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
class AppBoxKitGlassCard extends StatelessWidget {
  const AppBoxKitGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.wantNative = true,
    this.opaqueGlass = true,
  });

  /// The card content.
  final Widget child;

  /// Inner padding around [child], applied on every tier. Defaults to 16dp on
  /// all sides so content never touches the card edge (the glass tier paints
  /// flush to its bounds); pass [EdgeInsets.zero] for a full-bleed child.
  final EdgeInsets? padding;

  /// Corner radius. On the glass tier this maps to
  /// [LiquidGlassConfig.cornerRadius] (rect shape); on the frosted tier it
  /// maps to [AppBoxKitFrostedSurface.borderRadius]. `null` = 16 dp on both tiers
  /// (a card is always rect-shaped, never the capsule default).
  final double? borderRadius;

  /// Host opt-in to native chrome. `true` (default) renders Liquid Glass on
  /// iOS 26; `false` forces the Flutter-drawn frosted tier everywhere.
  final bool wantNative;

  /// Density ruling (default `true`): the native tier keeps real Liquid Glass
  /// densified by a partial-alpha surface tint (the vendor's `prominent`
  /// variant is a silent no-op — see the tier-1 comment), and the
  /// frosted tier becomes a fully opaque surface (tint token at alpha 1.0,
  /// platform-view-safe branch — card bodies may host CN platform views, and
  /// a BackdropFilter saveLayer cannot span the frame slices UiKitViews
  /// create, flutter#175048). `false` restores the old translucent read on
  /// both tiers ([CNGlassEffect.regular] + blurred frosted).
  final bool opaqueGlass;

  @override
  Widget build(BuildContext context) {
    final content =
        padding == null ? child : Padding(padding: padding!, child: child);

    // Tier 1 — iOS 26 Liquid Glass.
    if (wantNative && AppBoxKitPlatform.supportsLiquidGlass) {
      return LiquidGlassContainer(
        // The chrome gate below is the single hiding authority for this card.
        // The vendor's ModalHideMixin destroy path (Issue #53) must stay OFF
        // here: it swaps only the glass platform view for a placeholder while
        // `child` keeps rendering, which is exactly the "card glass vanishes
        // mid-drag but the buttons inside stay" artifact. The #53 bleed is now
        // contained natively (setTransitioning halo containment), so the
        // position-aware destroy is a defective duplicate for this surface.
        autoHideOnModal: false,
        config: LiquidGlassConfig(
          // A card is rect-shaped, not a capsule — LiquidGlassConfig honors
          // cornerRadius only in rect mode.
          shape: CNGlassEffectShape.rect,
          cornerRadius: borderRadius ?? 16,
          // Density ruling: still real Liquid Glass (the liquid-glass law
          // holds), densified via the native glass TINT — the one density
          // lever the vendor actually applies. Do NOT reach for
          // [CNGlassEffect.prominent] here: LiquidGlassContainerView.swift's
          // glassEffectForConfig() hard-codes `Glass.regular` ("prominent
          // glass API may be available in future"), so `prominent` is a
          // silent no-op on this container.
          effect: CNGlassEffect.regular,
          tint: opaqueGlass
              ? Theme.of(context)
                  .colorScheme
                  .surfaceContainerLowest
                  .withValues(alpha: 0.45)
              : null,
        ),
        child: content,
      ).chromeGated();
    }
    // Tier 2 — Flutter-drawn frosted (Android / fallback / wantNative: false).
    // One path on purpose: ADR 0010 makes the frosted material the correct
    // content-layer surface on EVERY non-iOS-26 tier, and unlike the old
    // Material Card it can't desync visually from the iOS glass tier.
    if (opaqueGlass) {
      // Same frosted read, opaque base — mirrors the sheet's opaque branch:
      // tint token at alpha 1.0 makes the backdrop blur invisible anyway, so
      // take the platform-view-safe branch (no BackdropFilter saveLayer).
      return Builder(
        builder: (BuildContext context) => AppBoxKitFrostedSurface(
          borderRadius: borderRadius ?? 16,
          platformViewSafe: true,
          tint: Theme.of(context)
              .colorScheme
              .surfaceContainerLowest
              .withValues(alpha: 1.0),
          child: content,
        ),
      );
    }
    return AppBoxKitFrostedSurface(
      borderRadius: borderRadius ?? 16,
      child: content,
    );
  }
}
