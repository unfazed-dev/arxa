import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'arxa_kit_native_chrome_gate.dart';

/// Adaptive range slider. On Android it renders `m3e_collection`'s
/// [RangeSliderM3E] (real Material 3 Expressive). On iOS 26+ it renders a
/// native [CNRangeSlider] — a single platform view with **two real `UISlider`
/// thumbs**, so Liquid Glass fires on each thumb on press, matching
/// [ArxaKitNativeSlider]'s thumb beside it. UIKit has no two-thumb slider, so the
/// native view routes each touch to the nearer thumb itself; this is the only
/// way to get *native* glass on a range control (a Flutter-painted track with
/// display-only sliders can't, because `IgnorePointer` starves the native
/// thumbs of the press that activates glass). Older Apple OSes (no Liquid
/// Glass) take a Cupertino-styled Material [RangeSlider] fallback. The kit
/// ships native chrome on Android with **no native code of its own**.
///
/// The public surface is **primitives only** ([values], [min], [max],
/// [onChanged]) so hosts never import `m3e_collection` or
/// `cupertino_native_better`. [onChanged] is nullable: `null` disables the
/// control on all tiers.
class ArxaKitNativeRangeSlider extends StatelessWidget {
  const ArxaKitNativeRangeSlider({
    super.key,
    required this.values,
    this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
  });

  /// Current selection. Each value should be within [min]…[max]; each tier
  /// clamps out-of-range values defensively.
  final RangeValues values;

  /// Notified on user drag. `null` disables the control.
  final ValueChanged<RangeValues>? onChanged;

  /// Minimum value (inclusive). Defaults to 0.0.
  final double min;

  /// Maximum value (inclusive). Defaults to 1.0.
  final double max;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive range slider. Apple → native CNRangeSlider
    // on iOS/macOS 26+ (real glass thumbs), else a Cupertino-styled Material
    // RangeSlider fallback. Else → Material RangeSlider.
    if (ArxaKitPlatform.supportsComposeM3E) return _m3e(context);
    // Glass gate mirrors CNSlider/CNRangeSlider's own decision exactly —
    // `defaultTargetPlatform ∈ {iOS, macOS}` AND host supports Liquid Glass —
    // so the kit never disagrees with the CN render path. Reading
    // defaultTargetPlatform also lets tests force the Material fallback via
    // debugDefaultTargetPlatformOverride (see withAndroidFallback).
    final appleGlass = (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        PlatformVersion.supportsLiquidGlass;
    if (appleGlass) {
      final scheme = Theme.of(context).colorScheme;
      return CNRangeSlider(
        values: values,
        // CNRangeSlider.onChanged is required non-null: a kit `null` means
        // "disabled", so hand it a no-op and drop the enabled flag.
        onChanged: onChanged ?? (_) {},
        enabled: onChanged != null,
        min: min,
        max: max,
        // Wire the active track to the kit theme's accent so the CN control
        // never falls back to a default tint in any host.
        trackColor: scheme.primary,
        trackBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
      ).chromeGated();
    }
    if (ArxaKitPlatform.isIOS) return _cupertinoStyled(context);
    return RangeSlider(
      values: values,
      onChanged: onChanged,
      min: min,
      max: max,
    );
  }

  /// Material [RangeSlider] restyled to Cupertino vocabulary: 4pt track,
  /// white shadowed thumbs, no pressed overlay halo, theme-primary active
  /// track — the Apple-tier fallback when Liquid Glass is unavailable
  /// (pre-iOS/macOS 26).
  Widget _cupertinoStyled(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.12),
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        rangeThumbShape: const RoundRangeSliderThumbShape(
          enabledThumbRadius: 13.5,
          elevation: 3,
          pressedElevation: 6,
        ),
      ),
      child: RangeSlider(
        values: values,
        onChanged: onChanged,
        min: min,
        max: max,
      ),
    );
  }

  // ponytail: RangeSliderM3E exposes divisions/labels/etc. that the kit doesn't
  // surface yet — add primitives only when a host needs them. Both tiers take a
  // nullable onChanged, so the kit's null passes through unchanged (disables).
  Widget _m3e(BuildContext context) => RangeSliderM3E(
        values: values,
        onChanged: onChanged,
        min: min,
        max: max,
      );
}
