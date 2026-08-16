import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';

/// A bundled-asset image with a token-styled placeholder fallback. Pure-
/// Flutter on every tier — there is **no** native (Liquid-Glass /
/// M3-Expressive) image surface, so this widget is named `AppBoxKitImage` (a
/// content widget), **not** `AppBoxKitNativeImage`. See `core/NATIVE_COMPONENTS.md`
/// ("Content widgets") — the native-component matrix's closed-set claim is
/// about chrome surfaces; an image is content.
///
/// Three behaviours worth naming:
/// - **Placeholder until decoded** — before the first frame decodes, the slot
///   shows the [placeholder] glyph on the fill color; once decoded the image
///   swaps in (via [Image.asset]'s `frameBuilder`). No animated cross-fade by
///   default — the swap is instant; a host wanting a fade wraps this widget.
/// - **Honest fallback on error** — if the asset is missing/corrupt, the
///   `errorBuilder` keeps the placeholder glyph on screen instead of the
///   framework's red error box, so an unknown asset path degrades gracefully
///   instead of crashing a screen.
/// - **Radius** — [ClipRRect] clips the image to [radius] (default [abxRad16]),
///   so rounded product imagery is one parameter, not a wrapping widget.
///
/// The kit ships no bundled image assets, so the happy-path decode is
/// exercised by host tests against host-bundled assets; the widget tests
/// here cover the fallback (no asset needed) + construction wiring.
class AppBoxKitImage extends StatelessWidget {
  const AppBoxKitImage({
    super.key,
    required this.asset,
    this.size,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius,
    this.placeholder,
    this.semanticLabel,
  }) : assert(
          size == null || (width == null && height == null),
          'Pass either size (square) or width/height, not both.',
        );

  /// Asset path for [Image.asset], e.g.
  /// `'assets/images/shop/product_food_images/p1-protein.jpg'`.
  final String asset;

  /// Square shortcut — sets both [width] and [height]. Mutually exclusive
  /// with them.
  final double? size;

  /// Width in logical px. Ignored when [size] is set.
  final double? width;

  /// Height in logical px. Ignored when [size] is set.
  final double? height;

  /// How to inscribe the image into the slot. Defaults to [BoxFit.cover] so a
  /// product photo fills its rounded frame without distortion.
  final BoxFit fit;

  /// Corner radius. Defaults to [abxRad16].
  final double? radius;

  /// Glyph drawn over the fill color before the first frame decodes and on
  /// load error. Defaults to [AppBoxKitGlyphs.photo].
  final AppBoxKitGlyph? placeholder;

  /// Accessibility label forwarded to [Image.asset].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = placeholder ?? AppBoxKitGlyphs.photo;
    final w = size ?? width;
    final h = size ?? height;
    final r = radius ?? abxRad16;

    Widget fallback() => Container(
          width: w,
          height: h,
          color: scheme.surfaceContainer,
          alignment: Alignment.center,
          child: Icon(glyph.icon, color: scheme.onSurfaceVariant),
        );

    // An empty asset is a caller bug. There is no platform branch here —
    // [Image.asset] resolves bundle keys on every tier (incl. web), and the
    // `errorBuilder` below is the single honest fallback if the asset is
    // missing/corrupt. No `dart:io` import: the kit stays web-safe.
    if (asset.isEmpty) {
      return _clip(r, fallback());
    }

    return _clip(
      r,
      Image.asset(
        asset,
        width: w,
        height: h,
        fit: fit,
        semanticLabel: semanticLabel,
        errorBuilder: (_, __, ___) => fallback(),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          // First frame not decoded yet — show the placeholder; the real
          // image replaces it via the frameBuilder return once `frame` is
          // non-null. This is the standard asset-image loading idiom.
          return fallback();
        },
      ),
    );
  }

  Widget _clip(double r, Widget child) =>
      ClipRRect(borderRadius: BorderRadius.circular(r), child: child);
}
