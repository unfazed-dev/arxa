import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:appbox_kit_core/platform/kit_platform.dart';
import 'kit_native_chrome_gate.dart';

/// Adaptive slider. On Android it renders `m3e_collection`'s [SliderM3E]
/// (real Material 3 Expressive); everywhere else it delegates to [CNSlider],
/// which renders native Liquid Glass on iOS/macOS 26+ and a Cupertino/Material
/// fallback below — so the kit ships genuine native chrome with **no native
/// code of its own**.
///
/// The public surface is **primitives only** ([value], [min], [max],
/// [divisions], [activeColor]) so hosts never import either underlying dep.
/// [onChanged] is nullable: `null` disables the control on both tiers.
class KitNativeSlider extends StatelessWidget {
  const KitNativeSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
  });

  /// Current slider value. Should be within [min]…[max]; each tier clamps
  /// out-of-range values defensively.
  final double value;

  /// Notified on user drag. `null` disables the control.
  final ValueChanged<double>? onChanged;

  /// Minimum value (inclusive). Defaults to 0.0.
  final double min;

  /// Maximum value (inclusive). Defaults to 1.0.
  final double max;

  /// Optional discrete step count. Maps to [SliderM3E]'s `divisions` directly
  /// and to [CNSlider]'s continuous `step` as `(max - min) / divisions`.
  final int? divisions;

  /// Active-track/accent color. Forwarded to [CNSlider] as `trackColor`.
  // ponytail: SliderM3E is theme-driven (no per-instance color param), so this
  // is intentionally dropped on the Android tier. Expose an M3E token override
  // only if a host ever needs to recolor the Material 3 Expressive slider.
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive slider. Else → CNSlider, which self-degrades
    // glass → Cupertino → Material.
    if (KitPlatform.supportsComposeM3E) return _m3e(context);
    return CNSlider(
      value: value,
      // CNSlider.onChanged is required-non-null: a kit `null` means "disabled",
      // so hand it a no-op and drop the enabled flag.
      onChanged: onChanged ?? (_) {},
      enabled: onChanged != null,
      min: min,
      max: max,
      // Explicitly wire the active track to the kit theme's accent so the CN
      // control never falls back to CupertinoColors.activeBlue in any host.
      trackColor: activeColor ?? Theme.of(context).colorScheme.primary,
      step: _cnStep,
    ).chromeGated();
  }

  /// Converts the kit's discrete [divisions] count into CNSlider's continuous
  /// step size. Guards against zero/negative spans so the native control never
  /// receives a degenerate step.
  double? get _cnStep {
    final d = divisions;
    if (d == null || d <= 0) return null;
    final span = max - min;
    if (span <= 0) return null;
    return span / d;
  }

  // ponytail: SliderM3E is theme-driven (no per-instance color param), so
  // [activeColor] is intentionally dropped on this tier — see field doc.
  Widget _m3e(BuildContext context) => SliderM3E(
        value: value,
        onChanged: onChanged,
        min: min,
        max: max,
        divisions: divisions,
      );
}
