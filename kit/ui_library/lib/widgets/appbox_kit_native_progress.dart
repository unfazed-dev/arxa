import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show CircularProgressIndicatorM3E, LinearProgressIndicatorM3E;

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

/// Which progress geometry the kit should render.
enum _KitProgressVariant { linear, circular }

/// Adaptive progress indicator — 2-way gate (Android M3 Expressive vs. a
/// Flutter fallback), in two geometries chosen by constructor:
///
/// - [AppBoxKitNativeProgress.linear] — a horizontal bar. Android →
///   [LinearProgressIndicatorM3E]; else → Material [LinearProgressIndicator].
/// - [AppBoxKitNativeProgress.circular] — a ring. Android →
///   [CircularProgressIndicatorM3E]; else → a Flutter fallback (see below).
///
/// The public surface is **primitives only** ([value], [color]). [value] is
/// `null` for indeterminate animation and a 0.0–1.0 fraction for determinate
/// progress — the same convention on every tier.
///
// ponytail: this is a 2-way gate (no real cupertino_native_better progress
// widget exists), so off-Android there is no Liquid Glass tier to route to —
// the fallback is the Flutter-native widget. Construct via the named
// factories; the private constructor carries the variant through build.
class AppBoxKitNativeProgress extends StatelessWidget {
  const AppBoxKitNativeProgress._({
    super.key,
    required _KitProgressVariant variant,
    this.value,
    this.color,
  }) : _variant = variant;

  /// Linear (horizontal bar) progress indicator.
  factory AppBoxKitNativeProgress.linear({
    Key? key,
    double? value,
    Color? color,
  }) =>
      AppBoxKitNativeProgress._(
        key: key,
        variant: _KitProgressVariant.linear,
        value: value,
        color: color,
      );

  /// Circular (ring) progress indicator.
  factory AppBoxKitNativeProgress.circular({
    Key? key,
    double? value,
    Color? color,
  }) =>
      AppBoxKitNativeProgress._(
        key: key,
        variant: _KitProgressVariant.circular,
        value: value,
        color: color,
      );

  /// Progress fraction 0.0–1.0, or `null` for indeterminate animation.
  final double? value;

  /// Active/accent color. `null` defers to each tier's theme default.
  final Color? color;

  final _KitProgressVariant _variant;

  @override
  Widget build(BuildContext context) {
    // Wire the accent to the kit theme so no tier falls back to a platform
    // default (Cupertino grey) in any host.
    final accent = color ?? Theme.of(context).colorScheme.primary;
    // Android → real M3 Expressive progress. Else → Flutter fallback.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(accent);
    switch (_variant) {
      case _KitProgressVariant.linear:
        return LinearProgressIndicator(value: value, color: accent);
      case _KitProgressVariant.circular:
        // ponytail: CupertinoActivityIndicator is indeterminate-only, so a
        // determinate [value] off-Android falls back to Material (which CAN
        // render a fraction). Indeterminate — the common case — stays Cupertino
        // for an iOS-native feel on the non-Android tier.
        return value == null
            ? CupertinoActivityIndicator(color: accent)
            : CircularProgressIndicator(value: value, color: accent);
    }
  }

  Widget _m3e(Color activeColor) {
    switch (_variant) {
      case _KitProgressVariant.linear:
        return LinearProgressIndicatorM3E(
            value: value, activeColor: activeColor);
      case _KitProgressVariant.circular:
        // NOTE: the dep's circular class is `CircularProgressIndicatorM3E`
        // (the *file* is circular_progress_m3e.dart — name carries "Indicator").
        return CircularProgressIndicatorM3E(
            value: value, activeColor: activeColor);
    }
  }
}
