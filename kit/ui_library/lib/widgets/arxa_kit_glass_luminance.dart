import 'package:flutter/material.dart';

/// Inherited luminance declaration — how a surface tells the native-glass
/// controls sitting on it whether Liquid Glass will read correctly.
///
/// **Why this exists (the measured defect class).** Glass-styled native
/// buttons wash out on a bright OPAQUE base (labels measured illegible on
/// the iOS 26.5 simulator, 2026-08-16); the remedy is the filled-gray idiom
/// with on-surface monochrome ink (the sheet close button's fix). Before
/// this scope existed that remedy was applied per call site and the class
/// kept reappearing surface by surface. Now the SURFACE declares its
/// luminance once and every [ArxaKitNativeButton] / [ArxaKitNativeIconButton]
/// adapts automatically — one publisher, N consumers.
///
/// **Publishers.** [ArxaKitFrostedSurface] publishes on both of its
/// branches (the opaque no-saveLayer branch declares `opaque: true`, the
/// blurred branch `opaque: false`), so every sheet body, dialog body, glass
/// card frosted tier, opaque bar base, and drawer skin is covered with zero
/// host code. A host building its own opaque surface can wrap it in
/// [ArxaKitGlassLuminance] directly.
///
/// **Fallback.** Where NO scope exists, [arxaKitGlassDemotesOnBrightBase]
/// resolves the theme's scaffold background — an opaque base by definition —
/// so bare `Scaffold` surfaces (the notes auth panel's social buttons) adapt
/// too. A translucent declaration shadows the scaffold: a glass button on a
/// blurred card over a bright scaffold keeps its glass.
///
/// **The rule consumers apply** ([demotesGlass]): only `opaque &&
/// brightness == Brightness.light` demotes. Dark opaque surfaces keep glass
/// (the washout measurement was bright-base only; dark surfaces had a
/// separate, surface-side fix). `prominentGlass` never demotes — the
/// accent-filled CTA reads on bright bases. The escape hatch is the button
/// wrappers' `luminanceAdaptive: false` (glass deliberately floating over
/// bright imagery).
class ArxaKitGlassLuminance extends InheritedWidget {
  const ArxaKitGlassLuminance({
    super.key,
    required this.opaque,
    required this.brightness,
    required super.child,
  });

  /// Whether the surface is fully opaque (alpha 1.0 — no backdrop shows
  /// through). Only opaque bases can wash a glass label out; a translucent
  /// glass surface keeps its controls' glass.
  final bool opaque;

  /// The surface's resolved brightness (`ThemeData.estimateBrightnessForColor`
  /// of its fill — Flutter's own contrast discriminator, not a magic luma
  /// constant).
  final Brightness brightness;

  /// True when a glass-styled control on this surface should demote to the
  /// filled-gray idiom: the base is opaque AND bright.
  bool get demotesGlass => opaque && brightness == Brightness.light;

  /// The nearest declaration, or null when no ancestor publishes one.
  static ArxaKitGlassLuminance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArxaKitGlassLuminance>();

  @override
  bool updateShouldNotify(ArxaKitGlassLuminance oldWidget) =>
      opaque != oldWidget.opaque || brightness != oldWidget.brightness;
}

/// The consumer-side resolution: should a glass-styled control at [context]
/// demote to the bright-base idiom? The nearest [ArxaKitGlassLuminance]
/// declaration wins; absent one, the theme's scaffold background (an opaque
/// base by definition) decides.
bool arxaKitGlassDemotesOnBrightBase(BuildContext context) {
  final scope = ArxaKitGlassLuminance.maybeOf(context);
  if (scope != null) return scope.demotesGlass;
  return ThemeData.estimateBrightnessForColor(
          Theme.of(context).scaffoldBackgroundColor) ==
      Brightness.light;
}
