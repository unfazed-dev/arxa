import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive icon button. On Android it renders `m3e_collection`'s
/// [IconButtonM3E] (real Material 3 Expressive, shape-morphs on press);
/// everywhere else it delegates to [CNButton.icon], which renders native Liquid
/// Glass on iOS/macOS 26+ and a Cupertino/Material fallback below — so the kit
/// ships genuine native chrome with **no native code of its own**.
///
/// The public surface is **primitives only** ([icon] / [sfSymbol], [onPressed],
/// [color], [size]) so hosts never import either underlying dep.
///
/// [sfSymbol] is an SF Symbol name (e.g. `'star.fill'`, `'gear'`) routed through
/// CNButton's **native** icon path (`icon:` → [CNSymbol]) — native on all Apple
/// (iOS 13+/macOS 11+ via CNIcon), Flutter-Icon fallback on Android/web. [icon]
/// (a Material [IconData]) maps to CNButton's `customIcon` on the Apple tier
/// (the non-native glyph path) and to [IconButtonM3E]'s `icon` on Android.
/// Mirrors [AppBoxKitNativeButton]'s icon convention so the host passes primitives and
/// stays free of the dep.
///
/// [onPressed] is nullable: `null` disables the button on both tiers.
///
/// Changing the glyph (or [sfSymbol]) at runtime ANIMATES on the Apple
/// tiers: the update reaches the mounted native button in place (no
/// platform-view recreation) and the SF Symbol replace transition swaps the
/// glyphs — mic → stop → mic toggles read as one continuous control. This
/// is the idiom for stateful trailing actions (a voice recorder's button
/// IS its state). Keep the widget at the same tree position (same type,
/// same key) so the update flows as a prop change.
class AppBoxKitNativeIconButton extends StatelessWidget {
  const AppBoxKitNativeIconButton({
    super.key,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    this.onPressed,
    this.color,
    this.size,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Paired Material icon + SF Symbol (see [AppBoxKitGlyphs]). The preferred way to
  /// give the button an icon — one token, both tiers, no drift.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the Android/Material tier ([IconButtonM3E]) and the
  /// non-native fallback on the Apple tier (CNButton `customIcon`). Required to
  /// render anything on Android; an [sfSymbol] alone can't cross to M3E.
  /// Resolved from the raw `icon` override first, then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Native SF Symbol name, rendered via CNButton's native icon path on the
  /// Apple tier. Resolved from the raw `sfSymbol` override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Icon tint. On the Apple tier forwarded to [CNSymbol] and the button
  /// `tint`; on Android applied to the [Icon] glyph.
  // ponytail: IconButtonM3E is theme-driven (no per-instance color param), so
  // color is icon-level only on the Android tier.
  final Color? color;

  /// Icon point size. Honored per tier; null falls back to the kit default:
  /// 18pt on the Apple tier (HIG nav-bar/toolbar glyph scale — CNSymbol's own
  /// 24 default reads visibly oversized in bar contexts; mirrors
  /// [AppBoxKitNativeToolbar]'s 18pt symbols) and the M3E Icon default (24) on
  /// Android.
  final double? size;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive icon button. Else → CNButton.icon, which
    // self-degrades glass → Cupertino → Material.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    // Alpha-0 hide the native Liquid Glass button during route transitions
    // (+ modal overlays) so it can't leak over a route slide — AppBoxKitNativeChromeGate.
    return AppBoxKitNativeChromeGate(
        child: CNButton.icon(
      icon: sfSymbol == null
          ? null
          : CNSymbol(
              sfSymbol!,
              size: size ?? 18.0,
              color: color ?? Theme.of(context).colorScheme.primary,
            ),
      // Native-first (mirrors the FAB's guard): CNButton priority is
      // imageAsset > customIcon > icon, so an always-set customIcon would
      // shadow the SF Symbol path and force the rasterized custom-icon branch.
      // Pass the Material glyph only when there is no symbol equivalent.
      customIcon: sfSymbol == null ? icon : null,
      onPressed: onPressed,
      tint: color,
      config: CNButtonConfig(
        customIconSize: size ?? 18.0,
        // The native tier is a UiKitView (no intrinsic width) → stretches to
        // fill its parent's loose constraints. shrinkWrap makes CNButton measure
        // the native button and pin width to it, matching every other tier.
        // ponytail: hardcoded true — expose a param only if a host ever wants a
        // full-bleed button.
        shrinkWrap: true,
      ),
    ));
  }

  // ponytail: IconButtonM3E is theme-driven (no per-instance color/variant
  // param), so [color] is applied to the Icon glyph only. Expose a
  // variant/shape map only if a host ever needs them.
  Widget _m3e(BuildContext context) => IconButtonM3E(
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
      );
}

/// Shared implied leading for the kit app bars ([AppBoxKitNativeAppBar] +
/// [AppBoxKitNativeSliverAppBar]). When the host passed no [leading] and the route
/// can be dismissed, the Flutter-drawn tiers (CupertinoNavigationBar on iOS,
/// Material AppBar/SliverAppBar elsewhere) build the back affordance as a
/// [AppBoxKitNativeIconButton] with [AppBoxKitGlyphs.back] — the SAME widget the trailing
/// action slots use — instead of the tier's stock back button
/// (`CupertinoNavigationBarBackButton` / `BackButton`), which drifts visually
/// from the kit action buttons. The M3E tiers are real native chrome and keep
/// their own implied leading (untouched).
///
/// Behavior mirrors the stock buttons: pop via `Navigator.maybePop` and the
/// same a11y semantics (`backButtonLabel`, `button: true`,
/// `excludeSemantics: true` — copied from CupertinoNavigationBarBackButton).
/// Returns [leading] unchanged when the host supplied one; null when the tier
/// should imply its own (hamburger etc.).
Widget? appBoxKitImpliedAppBarLeading(
  BuildContext context, {
  required Widget? leading,
  required bool automaticallyImplyLeading,
}) {
  if (leading != null || !automaticallyImplyLeading) return leading;
  if (!(ModalRoute.of(context)?.impliesAppBarDismissal ?? false)) return null;
  return Semantics(
    container: true,
    button: true,
    excludeSemantics: true,
    label: CupertinoLocalizations.of(context).backButtonLabel,
    child: AppBoxKitNativeIconButton(
      glyph: AppBoxKitGlyphs.back,
      onPressed: () => Navigator.maybePop(context),
    ),
  );
}
