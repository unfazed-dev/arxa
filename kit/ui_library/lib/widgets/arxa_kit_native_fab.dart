import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'arxa_kit_fab_morph.dart';
import 'arxa_kit_native_chrome_gate.dart';

/// Adaptive floating-action button. On Android it renders `m3e_collection`'s
/// [FabM3E] (round) or [ExtendedFabM3E] (when [label] is non-null) — real
/// Material 3 Expressive; everywhere else it delegates to a prominent-glass
/// [CNButton], which renders native Liquid Glass on iOS/macOS 26+ and a
/// Cupertino/Material fallback below — so the kit ships genuine native chrome
/// with **no native code of its own**.
///
/// The public surface is **primitives only** ([icon] / [sfSymbol], [label],
/// [onPressed]) so hosts never import either underlying dep. [label] selects
/// the shape on every tier: `null` → round FAB, non-null → extended FAB.
///
/// [sfSymbol] is an SF Symbol name routed through CNButton's native icon path
/// on the Apple tier; [icon] (a Material [IconData]) is the M3E/Android glyph
/// and the non-native fallback on Apple. On Apple the SF Symbol is preferred
/// (native-first); [icon] is used only when [sfSymbol] is null — see
/// [ArxaKitNativeButton] for the same convention.
///
/// [onPressed] is nullable: `null` disables the button on every tier.
class ArxaKitNativeFab extends StatelessWidget {
  const ArxaKitNativeFab({
    super.key,
    this.icon,
    this.sfSymbol,
    this.label,
    this.onPressed,
  });

  /// Material glyph for the Android tier ([FabM3E]/[ExtendedFabM3E]) and the
  /// non-native fallback on the Apple tier (CNButton `customIcon`). Defaults to
  /// [Icons.add] on the round Android tier when null.
  final IconData? icon;

  /// Native SF Symbol name (e.g. `'plus'`, `'square.and.pencil'`), rendered via
  /// CNButton's native icon path on the Apple tier. Preferred over [icon]
  /// there; ignored on Android (SF Symbol names can't cross to M3E).
  final String? sfSymbol;

  /// Label. `null` renders a round FAB; non-null renders an extended FAB on
  /// every tier.
  final String? label;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive FAB. Else → prominent-glass CNButton, which
    // self-degrades glass → Cupertino → Material.
    if (ArxaKitPlatform.supportsComposeM3E) return _m3e(context);
    return _glass(context);
  }

  Widget _m3e(BuildContext context) {
    // label non-null → extended; else round.
    if (label != null) {
      return ExtendedFabM3E(
        label: Text(label!),
        icon: icon == null ? null : Icon(icon),
        onPressed: onPressed,
      );
    }
    // ArxaKitFabMorph (not FabM3E): a filled/elevated M3E FAB that shape-morphs on
    // press like the kit's icon buttons. FabM3E's shape is static — no morph.
    return ArxaKitFabMorph(
      icon: Icon(icon ?? Icons.add),
      onPressed: onPressed,
    );
  }

  Widget _glass(BuildContext context) {
    // ponytail: native-first — SF Symbol wins on Apple; Material icon is the
    // fallback only when sfSymbol is null. Avoids customIcon shadowing the
    // native glyph (CNButton priority: imageAsset > customIcon > icon).
    final symbol = sfSymbol == null
        ? null
        // 22pt (not 24pt): SF Symbols draw their ink ~edge-to-edge in the
        // point box (measured: 'plus' ink ≈ 1.0× pointSize), so 24pt reads
        // 0.43 of the 56pt circle. 22pt lands on the ~0.40 Apple-native
        // optical weight for circular buttons.
        : CNSymbol(
            sfSymbol!,
            size: 22,
            // The iOS glass FAB is translucent (not an accent-filled surface),
            // so the glyph itself carries the kit accent — primary, not
            // onPrimary (near-white paper, which vanishes on light glass).
            color: Theme.of(context).colorScheme.primary,
          );
    final customIcon = sfSymbol == null ? icon : null;
    if (label != null) {
      return CNButton(
        label: label!,
        onPressed: onPressed,
        icon: symbol,
        customIcon: customIcon,
        config: CNButtonConfig(
          style: CNButtonStyle.prominentGlass,
          // The native tier is a UiKitView (no intrinsic width) → pin width to
          // the measured native button so it sizes like the M3E tiers.
          shrinkWrap: true,
        ),
      ).chromeGated();
    }
    return CNButton.icon(
      icon: symbol,
      customIcon: customIcon,
      onPressed: onPressed,
      config: CNButtonConfig(
        style: CNButtonStyle.prominentGlass,
        shrinkWrap: true,
        // Match the Android FabM3E footprint (56pt circle) with a 22pt glyph
        // (~0.40 optical ratio, see CNSymbol size above). CNButton's
        // auto-circle (iconSize*2, min 44) would yield only 44pt — visibly
        // smaller than the M3E tier. 17pt padding centers the glyph natively
        // (17+22+17 = 56); width/minHeight pin the Flutter box to the same
        // circle.
        width: 56.0,
        minHeight: 56.0,
        padding: const EdgeInsets.all(17.0),
      ),
    ).chromeGated();
  }
}
