import 'package:m3e_collection/m3e_collection.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive CTA button. Delegates to `cupertino_native_better`'s [CNButton],
/// which renders **real Liquid Glass** on iOS/macOS 26+, a `CupertinoButton` on
/// older Apple OSes, and a Material fallback on Android/web — so the kit ships
/// genuine glass with **no native code of its own**.
///
/// Default style is Liquid Glass ([CNButtonStyle.glass]); pass [style] for
/// variants (`prominentGlass`, `filled`, `bordered`, …) and [glassEffectUnionId]
/// to merge adjacent buttons into one unified glass pill (e.g. a toolbar row).
///
/// Content is **primitives** ([label] + optional [sfSymbol]) so CNButton can
/// hand them to the native tier. For a rich/compound child, use [CNButton]
/// directly.
///
/// [sfSymbol] is an SF Symbol name (e.g. `'star.fill'`, `'gear'`) routed through
/// CNButton's **native** icon path (`icon:` → [CNSymbol]) — native on all Apple
/// (iOS 13+/macOS 11+ via CNIcon), Flutter-Icon fallback on Android/web. Do NOT
/// take a Material [IconData] here: that maps to CNButton's `customIcon`, which
/// is the non-native glyph path (priority `imageAsset > customIcon > icon`, so a
/// Material IconData would shadow the native SF Symbol). Mirrors [AppBoxKitTab]'s
/// `sfSymbol` so the host passes a plain string and stays free of the dep.
class AppBoxKitNativeButton extends StatelessWidget {
  const AppBoxKitNativeButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.glyph,
    String? sfSymbol,
    IconData? icon,
    this.sfSymbolSize = 13.0,
    this.sfSymbolColor,
    this.style = AppBoxKitButtonStyle.glass,
    this.glassEffectUnionId,
    this.imagePadding = 6.0,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  final VoidCallback? onPressed;
  final String label;

  /// Paired Material icon + SF Symbol (see [AppBoxKitGlyphs]). The preferred way to
  /// give the button an icon — one token, both tiers, no drift.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Native SF Symbol name, rendered via CNButton's native icon path.
  /// Resolved from the raw `sfSymbol` override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Material glyph for the **non-Apple tiers** (Android M3E / Material). SF
  /// Symbol names can't cross to Material, so a [glyph] carries both; null
  /// renders iconless off-Apple. Resolved from the raw `icon` override first,
  /// then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Symbol point size. Defaults to 13, NOT the title's 17: CNButton's glass
  /// pipeline renders the glyph ~1.3× the configured point size (measured on
  /// the iOS 26.5 sim: config 17 → 22.3pt glyph, config 8 → 12.7pt, config 13
  /// → 17.0pt = 1.34× the body-17 title's cap height, the native
  /// UIButton/Label proportion). 17 here looks visibly oversized.
  final double sfSymbolSize;

  /// Symbol color. Defaults to the theme's primary color, matching CNButton's
  /// own tint fallback (the title color) — otherwise the native tier renders
  /// the glyph in the default label color (black) next to a tinted title.
  /// Pass explicitly for filled/prominent styles where content is on accent.
  final Color? sfSymbolColor;

  final AppBoxKitButtonStyle style;
  final String? glassEffectUnionId;

  /// Distance between the symbol and the title. UIButton.Configuration's own
  /// imagePadding default is 0 (frames flush, ~3pt optical air from glyph
  /// bearings) — tighter than Apple's typical icon+text buttons and than
  /// CNButton's SwiftUI glass path (8). 6 splits the difference.
  final double imagePadding;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive button (shape-morphs on press). Else →
    // CNButton, which self-degrades glass → Cupertino → Material.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    // Button-class controls are native Liquid Glass everywhere, INCLUDING
    // scrollables, and every style passes through 1:1 (informed allowlist,
    // ratified 2026-08-13: home's 7 in-scroll icon buttons render clean —
    // CNButton-backed views are exposure-safe; the continuous controls
    // (slider/switch/search bar/text field) stay demoted in scroll. See
    // docs/liquid-glass-allowlist.md §2).
    return CNButton(
      label: label,
      onPressed: onPressed,
      icon: sfSymbol == null
          ? null
          : CNSymbol(
              sfSymbol!,
              size: sfSymbolSize,
              color: sfSymbolColor ?? Theme.of(context).colorScheme.primary,
            ),
      config: CNButtonConfig(
        // ponytail: names mirror CNButtonStyle 1:1; byName beats a switch.
        style: CNButtonStyle.values.byName(style.name),
        glassEffectUnionId: glassEffectUnionId,
        imagePadding: imagePadding,
        // The native tier is a UiKitView (no intrinsic width) → stretches to
        // fill its parent's loose constraints. shrinkWrap makes CNButton measure
        // the native button and pin width to it, matching every other tier
        // (M3E / Cupertino / Material are all content-sized). ponytail: hardcoded
        // true — expose a param only if a host ever wants a full-bleed button.
        shrinkWrap: true,
      ),
    ).chromeGated();
  }

  // M3E has no glass, so map by *emphasis* instead of by look (ButtonM3EStyle
  // ladder: filled > tonal > outlined > text): the high-emphasis styles
  // (prominentGlass / filled / borderedProminent) → filled, the mid-emphasis
  // surfaces (glass / gray / tinted) → tonal, bordered → outlined, and plain
  // (text-only on Apple) → text — so a secondary iOS button never renders as
  // a second primary CTA on Android (e.g. auth's plain 'Create Account' next
  // to its prominentGlass 'Sign In').
  static const _m3eStyle = <AppBoxKitButtonStyle, ButtonM3EStyle>{
    AppBoxKitButtonStyle.plain: ButtonM3EStyle.text,
    AppBoxKitButtonStyle.gray: ButtonM3EStyle.tonal,
    AppBoxKitButtonStyle.tinted: ButtonM3EStyle.tonal,
    AppBoxKitButtonStyle.bordered: ButtonM3EStyle.outlined,
    AppBoxKitButtonStyle.borderedProminent: ButtonM3EStyle.filled,
    AppBoxKitButtonStyle.filled: ButtonM3EStyle.filled,
    AppBoxKitButtonStyle.glass: ButtonM3EStyle.tonal,
    AppBoxKitButtonStyle.prominentGlass: ButtonM3EStyle.filled,
  };

  Widget _m3e(BuildContext context) => ButtonM3E(
        onPressed: onPressed,
        label: Text(label),
        icon: icon == null ? null : Icon(icon),
        style: _m3eStyle[style]!,
      );
}

/// Kit-owned mirror of the dep's button styles so hosts choose a variant
/// without importing `cupertino_native_better`. Names match [CNButtonStyle].
enum AppBoxKitButtonStyle {
  plain,
  gray,
  tinted,
  bordered,
  borderedProminent,
  filled,
  glass,
  prominentGlass,
}
