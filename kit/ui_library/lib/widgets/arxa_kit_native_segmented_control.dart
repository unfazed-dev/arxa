import 'package:m3e_collection/m3e_collection.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'arxa_kit_native_chrome_gate.dart';

/// Adaptive segmented control — three-tier:
///
/// - **iOS 26 native** — delegates to `cupertino_native_better`'s
///   [CNSegmentedControl] (a real `UISegmentedControl` via hybrid composition).
/// - **Android Material 3 Expressive** — `ButtonGroupM3E` as a *connected
///   button group*. M3 Expressive **deprecates the segmented button** in favour
///   of the connected button group, so that is the SSOT-correct M3E widget:
///   single-select via [selectedIndex]; the selected segment gets a tonal
///   (`secondaryContainer`) fill and shape-morphs to a full pill.
/// - **Flutter fallback** — `CupertinoSlidingSegmentedControl` on iOS < 26 /
///   macOS, Material 3 [SegmentedButton] on desktop/web.
///
/// The owner holds [selectedIndex]; the control is a projection of it and
/// reports taps via [onChanged] (never a second source of truth). See
/// `NATIVE_COMPONENTS.md` (`segmented / tabs` row) and `DESIGN_REFERENCES.md`.
class ArxaKitNativeSegmentedControl extends StatelessWidget {
  const ArxaKitNativeSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 32.0,
    this.color,
    this.native,
  });

  /// Segment labels, in order.
  final List<String> segments;

  /// Index of the selected segment (owner-held).
  final int selectedIndex;

  /// Fires with the tapped segment index.
  final ValueChanged<int> onChanged;

  /// Control height (native + Cupertino tiers).
  final double height;

  /// Accent/tint. Defaults to the theme's primary colour.
  final Color? color;

  /// Force native-chrome/fallback. `null` = auto (glass on iOS 26, M3E on
  /// Android).
  final bool? native;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    final wantNative = native ?? ArxaKitPlatform.supportsNativeChrome;
    // Tier 1 — iOS 26 Liquid Glass.
    if (wantNative && ArxaKitPlatform.supportsLiquidGlass) {
      return SizedBox(
        height: height,
        child: CNSegmentedControl(
          labels: segments,
          selectedIndex: selectedIndex,
          onValueChanged: onChanged,
          height: height,
          color: tint,
          // UiKitView has no intrinsic width → stretches to fill without this.
          // shrinkWrap makes CNSegmentedControl measure the native control and
          // pin its width, matching the intrinsic-width fallback/M3E tiers.
          shrinkWrap: true,
          // Native glass in scrollables too — segmented joined the informed
          // allowlist (ratified 2026-08-13; home ran one clean above Flutter
          // text). First to re-demote if artifacts return — see
          // docs/liquid-glass-allowlist.md §2.
        ),
      ).chromeGated();
    }
    // Tier 2 — Android Material 3 Expressive: connected button group.
    if (wantNative && ArxaKitPlatform.supportsComposeM3E)
      return _m3e(context);
    // Tier 3 — Cupertino (Apple < 26) / Material (desktop/web).
    return _KitFallbackSegmentedControl(
      segments: segments,
      selectedIndex: selectedIndex,
      onChanged: onChanged,
      height: height,
    );
  }

  /// M3E connected button group — the SSOT replacement for the deprecated
  /// segmented button. `ButtonM3E` colours by *style* (the `selected` flag only
  /// morphs the shape), so the style is set per segment: selected → `tonal`
  /// (`secondaryContainer`, the M3 spec selected fill), unselected → `outlined`.
  /// `selection: true` gives the connected shape-morph (selected → full pill);
  /// `equalizeWidths` keeps segments uniform. Theme-driven — ignores [color].
  Widget _m3e(BuildContext context) {
    return ButtonGroupM3E(
      type: ButtonGroupM3EType.connected,
      shape: ButtonGroupM3EShape.square,
      selection: true,
      selectedIndex: selectedIndex,
      equalizeWidths: true,
      actions: [
        for (var i = 0; i < segments.length; i++)
          ButtonGroupM3EAction(
            label: Text(segments[i]),
            onPressed: () => onChanged(i),
            style: i == selectedIndex
                ? ButtonM3EStyle.tonal
                : ButtonM3EStyle.outlined,
          ),
      ],
    );
  }
}

/// Non-Liquid-Glass tier: Material on Android/desktop/web, Cupertino on Apple.
class _KitFallbackSegmentedControl extends StatelessWidget {
  const _KitFallbackSegmentedControl({
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    required this.height,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    switch (ArxaKitPlatform.targetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _cupertino(context);
      default:
        return _material(context);
    }
  }

  Widget _material(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // iOS-parity: purple (primary) active segment, matching the nav pill (M3's
    // default is the paler secondaryContainer). No density/shape overrides — a
    // negative visualDensity shrank the fill box below the outline and "cut"
    // the rounded end-corners; the default stadium rounds the end fills once
    // they're full-height, and SegmentedButton centers labels on its own.
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primary : null),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface),
      ),
      segments: [
        for (var i = 0; i < segments.length; i++)
          ButtonSegment<int>(value: i, label: Text(segments[i])),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }

  Widget _cupertino(BuildContext context) => SizedBox(
        height: height,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: selectedIndex,
          onValueChanged: (i) {
            if (i != null) onChanged(i);
          },
          children: {
            for (var i = 0; i < segments.length; i++) i: Text(segments[i]),
          },
        ),
      );
}
