import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart' show LoadingIndicatorM3E;

import 'package:appbox_kit_core/platform/kit_platform.dart';

/// Adaptive indeterminate loading spinner. Three tiers:
///
/// - **Android** → [LoadingIndicatorM3E] (real Material 3 Expressive morphing
///   shape, from `loading_indicator_m3e`).
/// - **iOS** → [CupertinoActivityIndicator] (the Flutter Cupertino spinner —
///   native-feeling on every iOS version).
/// - **else** (web / desktop) → [CircularProgressIndicator] (Material).
///
/// The public surface is **primitives only** ([size], [color]) so hosts never
/// import either underlying dep. This is a display widget — no interaction.
///
// ponytail: there is no cupertino_native_better loading indicator, so the
// iOS tier is the Flutter Cupertino spinner on every iOS version (no Liquid
// Glass variant exists in the dep to gate on supportsLiquidGlass). The gate
// is therefore platform-based (Android → iOS → else), not capability-based
// like the chrome widgets that own a real CN tier.
class KitNativeLoadingIndicator extends StatelessWidget {
  const KitNativeLoadingIndicator({super.key, this.size, this.color});

  /// Target square dimension (logical px) of the spinner. Each tier interprets
  /// this defensively: M3E → `BoxConstraints.tight(Size(size, size))`,
  /// Cupertino → `radius = size / 2`, Material → a `SizedBox` clip. `null`
  /// lets each tier use its own default sizing.
  final double? size;

  /// Accent/spinner color. `null` defers to each tier's theme default
  /// (M3E tokens / Cupertino default / Material theme primary).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive loading indicator. iOS → Cupertino spinner.
    // Else → Material CircularProgressIndicator.
    if (KitPlatform.supportsComposeM3E) return _m3e(context);
    if (KitPlatform.isIOS) return _cupertino(context);
    return CircularProgressIndicator(
        color: color ?? Theme.of(context).colorScheme.primary);
  }

  Widget _m3e(BuildContext context) => LoadingIndicatorM3E(
        color: color ?? Theme.of(context).colorScheme.primary,
        // LoadingIndicatorM3E sizes itself from M3E tokens by default; honor a
        // host [size] by pinning a tight square constraint.
        constraints:
            size == null ? null : BoxConstraints.tight(Size(size!, size!)),
      );

  Widget _cupertino(BuildContext context) {
    // CupertinoActivityIndicator is indeterminate-only and radius-driven:
    // treat [size] as a diameter and halve it. Default the tint to the kit
    // theme's accent so the spinner carries the kit colour, not Cupertino grey.
    final tint = color ?? Theme.of(context).colorScheme.primary;
    if (size == null) return CupertinoActivityIndicator(color: tint);
    return CupertinoActivityIndicator(color: tint, radius: size! / 2);
  }
}
