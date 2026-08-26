import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'arxa_kit_glass_luminance.dart';

/// Flutter-drawn frosted-glass surface — the kit's **content-layer glass
/// tier** (ADR 0010, part 2: glass tier split).
///
/// Apple's own guidance for iOS 26 is "don't use Liquid Glass in the content
/// layer" — platform-view glass is pinned chrome only (bars, FAB, input bar).
/// Anything that scrolls, clips, or animates (list cards, sheet bodies,
/// dialog bodies, drawer skins) belongs on this tier instead: a
/// [BackdropFilter] blur + saturation boost + theme-derived tint + a subtle
/// rim highlight — the standard-materials look, occlusion-safe by
/// construction because every pixel is Flutter-drawn (clips, transforms, and
/// scrims all compose correctly, and there is no `UiKitView` to bleed or
/// leak over route transitions).
///
/// Theme-aware: the tint rides `ColorScheme.surfaceContainerLowest` (the
/// kit's card/paper token) at a material alpha per brightness, and the rim
/// highlight follows — hosts set nothing.
///
/// Wave-2 consumers: sheet / dialog bodies should compose on this widget
/// directly (pass a larger [borderRadius], tune [blur]/[tint] if the sheet
/// material needs it) rather than re-rolling their own BackdropFilter card.
///
/// The public surface is **primitives only** ([child], [padding],
/// [borderRadius], [blur], [saturation], [tint]).
///
/// **The auto-opaque law** (rule 13, codified): a fully opaque fill makes
/// the backdrop blur invisible anyway, so a fully opaque [tint] takes the
/// no-saveLayer branch on its own — [platformViewSafe] is then redundant.
/// This is a discrete mode switch, NOT an interpolation: never animate tint
/// alpha across 1.0, or the saveLayer appears/disappears mid-animation.
///
/// **Luminance publisher.** Both branches wrap their child in an
/// [ArxaKitGlassLuminance] scope — the opaque branch declares the bright
/// base that demotes glass controls (the washout remedy), the blurred branch
/// declares "translucent — keep your glass" and shadows any outer opaque
/// scope. Hosts never wire this; it is what makes the luminance adaptation
/// global.
///
/// kimitail: one BackdropFilter = one saveLayer per surface — fine for cards
/// and sheet bodies; if a long list of frosted cards ever janks, the upgrade
/// path is liquid_glass_widgets (shader refraction, ADR 0010 research item 3),
/// not per-call-site caching.
class ArxaKitFrostedSurface extends StatelessWidget {
  const ArxaKitFrostedSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16,
    this.blur = 20,
    this.saturation = 1.2,
    this.tint,
    this.platformViewSafe = false,
  });

  /// When true, drops the [BackdropFilter] and renders a FULLY OPAQUE vibrant
  /// fill instead (same tint token, rim, shadow, radius). Required whenever
  /// the subtree may host platform views: a BackdropFilter saveLayer cannot
  /// span the frame slices UiKitViews create, so Flutter content inside it
  /// intermittently drops on device (flutter#175048;
  /// kit/core/NATIVE_COMPONENTS.md "a BackdropFilter cannot sample or cover
  /// platform-view pixels"). This is also Apple's own degrade: nested glass
  /// auto-converts to vibrant fill (WWDC25 design lab). Redundant (but
  /// harmless) when [tint] is fully opaque — the auto-opaque law takes this
  /// branch either way.
  final bool platformViewSafe;

  /// The surface content.
  final Widget child;

  /// Inner padding around [child]; `null` (default) = no padding — the
  /// caller owns spacing (matches [ArxaKitGlassCard], which pads before handing
  /// its content down).
  final EdgeInsets? padding;

  /// Corner radius in dp. Defaults to 16 (card); sheet bodies typically want
  /// the sheet radius (≈28 top corners).
  final double borderRadius;

  /// Backdrop blur sigma. 20 ≈ Apple's regular material; raise toward 30 for
  /// a thicker (prominent) material, lower for ultra-thin.
  final double blur;

  /// Backdrop saturation multiplier applied under the blur (Apple materials
  /// boost saturation so colors refracting through stay vivid). 1.0 = off.
  final double saturation;

  /// Tint override. `null` (default) = theme-derived:
  /// `ColorScheme.surfaceContainerLowest` at 72% (light) / 55% (dark).
  /// A fully opaque tint implies the no-saveLayer branch (the auto-opaque
  /// law in the class doc).
  final Color? tint;

  /// Saturation matrix (Rec. 709 luma weights) for [ColorFilter.matrix].
  static List<double> _saturationMatrix(double s) => [
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
        0, 0, 0, 1, 0,
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);

    // The auto-opaque law: a fully opaque fill makes the backdrop blur
    // invisible anyway, so an opaque tint alone selects the no-saveLayer
    // branch. platformViewSafe stays meaningful for translucent
    // platform-view-safe fills.
    final saveLayerFree =
        platformViewSafe || (tint != null && tint!.a >= 0.999);
    final resolvedTint = saveLayerFree
        // Alpha rides at FULL when no tint override is given — this branch
        // is what opaqueGlass surfaces (chips, bar bases) paint, and a
        // sub-1.0 default left dark-mode chips reading translucent with a
        // light-biased wash (measured 2026-08-17: left .116 / mid .111 /
        // right .143). A caller wanting translucency passes its own tint or
        // the blurred branch below.
        ? (tint ?? scheme.surfaceContainerLowest.withValues(alpha: 1.0))
        : (tint ??
            scheme.surfaceContainerLowest.withValues(alpha: dark ? 0.55 : 0.72));

    if (saveLayerFree) {
      return ArxaKitGlassLuminance(
        opaque: true,
        brightness: ThemeData.estimateBrightnessForColor(resolvedTint),
        child: Container(
          decoration: BoxDecoration(
            color: resolvedTint,
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.16 : 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: padding,
          child: child,
        ),
      );
    }

    return ArxaKitGlassLuminance(
      opaque: false,
      brightness: ThemeData.estimateBrightnessForColor(resolvedTint),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            // Soft ambient lift — part of the standard-materials read, subtle
            // enough to survive over busy backdrops.
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            // Saturate the backdrop first, then blur (ImageFilter.compose
            // applies inner → outer).
            filter: ImageFilter.compose(
              outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              inner: ColorFilter.matrix(_saturationMatrix(saturation)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: resolvedTint,
                borderRadius: radius,
                // Rim highlight — the bright hairline that reads as a glass
                // edge catching light.
                border: Border.all(
                  color: Colors.white.withValues(alpha: dark ? 0.16 : 0.45),
                ),
              ),
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
