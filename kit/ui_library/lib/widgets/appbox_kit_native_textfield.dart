import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextField;
import 'package:flutter/material.dart';
import 'package:text_field_m3e/text_field_m3e.dart' show TextFieldM3E;

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_input_tap_behavior.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive text field — three-tier, matching the rest of the `AppBoxKitNative*`
/// family (every sibling gates `supportsComposeM3E` → its vendored `_m3e` fork
/// on Android):
/// - **iOS 26 Liquid Glass** — [CNTextField] (real `UITextField` via
///   `cupertino_native_better`, `.glassEffect` capsule). Below iOS 26 the CN
///   tier still hosts a native SwiftUI `TextField` in a `systemGray6` capsule,
///   so the platform view is used on all iOS/macOS versions.
/// - **Android M3 Expressive** — [TextFieldM3E] (the vendored `text_field_m3e`
///   fork), the M3E focus shape-morph field that mirrors the split-button /
///   toolbar / FAB morph. Google has not shipped an *official* Flutter M3E text
///   field (flutter/flutter#168813), so the kit vendors one — a plain themed
///   Material [TextField] renders container-less by default (no filled surface)
///   and reads as a bare underline, out of step with the filled M3E siblings.
/// - **Fallback** (desktop/web, `wantNative: false`) — Material 3 [TextField].
///
/// The public surface is **primitives only** so hosts never import either
/// underlying dep. Pass a [TextEditingController] to read the value on submit
/// (the CN tier two-way-syncs it; the Material tier uses it natively).
class AppBoxKitNativeTextField extends StatelessWidget {
  const AppBoxKitNativeTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.minLines,
    this.maxLines,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.wantNative = true,
    this.dismissKeyboardOnOutsideTap = true,
    this.fillColor,
    this.borderRadius,
    this.tint,
    this.textColor,
    this.placeholderColor,
  });

  /// Owns the input text. Two-way synced on the Liquid Glass tier (programmatic
  /// writes forward to native; native keystrokes write back) and used natively
  /// on the Material tiers.
  final TextEditingController? controller;

  /// Placeholder text. Maps to [CNTextField.placeholder] and the Material
  /// [InputDecoration.hintText]. Prefer this over [hintText]; [hintText] is kept
  /// for symmetry with [AppBoxKitNativeSearchBar.hint].
  final String? placeholder;

  /// Alias for [placeholder] (the search-bar naming). If both are passed,
  /// [placeholder] wins.
  final String? hintText;

  /// `true` → obscured (passwords, OTP). Disables the CN tier's clear button.
  final bool obscureText;

  /// Keyboard type. Honored on every tier.
  final TextInputType? keyboardType;

  /// Multiline composer contract (with [maxLines]): minimum visible lines.
  /// `null` (default) = single-line field — the historical behavior. On the
  /// CN tier this switches the Swift field to `TextField(axis: .vertical)` +
  /// `lineLimit(min...max)` and the capsule grows natively; SecureField has no
  /// vertical axis, so `obscureText` fields stay single-line regardless.
  final int? minLines;

  /// Maximum lines; `null` with [minLines] = unbounded growth. Capped fields
  /// scroll internally past the cap on every tier.
  final int? maxLines;

  /// Autofocus on appearance.
  final bool autofocus;

  /// Whether the field accepts input. Material tiers render disabled state;
  /// the CN tier is built but non-interactive when `false`.
  final bool enabled;

  /// Fired on every keystroke.
  final ValueChanged<String>? onChanged;

  /// Fired on submit (return key).
  final ValueChanged<String>? onSubmitted;

  /// Host opt-out of native chrome. `true` (default) routes to [CNTextField]
  /// on iOS/macOS; `false` forces the Material [TextField] tier everywhere.
  final bool wantNative;

  /// Tap-outside keyboard dismissal default (see [AppBoxKitInputTapBehavior]).
  /// On by default; every tier is wrapped in the kit's grouped tap region, so
  /// tapping outside dismisses on both the Flutter and native focus tiers and
  /// re-tapping the focused field never drops the keyboard. Set false only
  /// when a screen drives focus itself.
  final bool dismissKeyboardOnOutsideTap;

  /// Background fill for the Material tiers (ignored on the CN glass tier,
  /// which owns its capsule surface). `null` = theme default.
  final Color? fillColor;

  /// Corner radius for the Material tiers' border (ignored on the CN tier).
  /// `null` = theme default.
  final double? borderRadius;

  /// Accent / caret / clear-button tint on the CN tier. `null` = the app
  /// theme's [ColorScheme.primary] so the native caret matches Flutter chrome.
  final Color? tint;

  /// Input text color on the CN tier. `null` = [ColorScheme.onSurface].
  /// Without an explicit color the native field falls back to UIKit's
  /// `.primary` label color, which ignores the app theme entirely and washes
  /// out on tinted (e.g. warm cream) surfaces.
  final Color? textColor;

  /// Placeholder color on the CN tier. `null` = [ColorScheme.onSurfaceVariant]
  /// — the theme's contrast-safe "hint on surface" token. The native default
  /// (`.secondary` at reduced alpha over a translucent glass capsule) has
  /// insufficient contrast on tinted backgrounds.
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    // iOS/macOS → CNTextField (Liquid Glass on iOS 26+, native SwiftUI capsule
    // below). Matches the search bar's `wantNative && supportsLiquidGlass`
    // shape, but the CN text field is valid on ALL iOS/macOS (it degrades to a
    // non-glass capsule), so we gate on platform rather than on the glass flag.
    // iOS-only: the vendored CNTextField registers no macOS factory, so a
    // macOS desktop host takes the Material tier below (an AppKitView for an
    // unregistered view type would crash at creation).
    final useNativeTier = wantNative && AppBoxKitPlatform.isIOS;
    if (useNativeTier) {
      // isDesktop covers macOS; the CN bridge switches UiKitView→AppKitView
      // internally. Android is excluded — it takes the Material M3E tier below.
      // Theme tokens are forwarded so the native text/placeholder/caret track
      // the app's ColorScheme instead of UIKit defaults, which lose contrast
      // on tinted surfaces (auth sheet regression: near-invisible
      // placeholders on the warm cream theme).
      final scheme = Theme.of(context).colorScheme;
      final field = CNTextField(
        controller: controller,
        placeholder: placeholder ?? hintText,
        obscureText: obscureText,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        tint: tint ?? scheme.primary,
        textColor: textColor ?? scheme.onSurface,
        placeholderColor: placeholderColor ?? scheme.onSurfaceVariant,
      ).chromeGated();
      // CNTextField has no `enabled` channel param; enforce the documented
      // "built but non-interactive" contract on the Flutter side.
      final Widget tier = enabled
          ? field
          : IgnorePointer(child: Opacity(opacity: 0.5, child: field));
      return _withInputTapBehavior(tier);
    }

    // Android M3 Expressive → the vendored [TextFieldM3E] fork (focus
    // shape-morph, matching the split-button/toolbar/FAB morph), gated exactly
    // like every AppBoxKitNative* sibling. `wantNative: false` skips it to the
    // Material fallback below.
    if (wantNative && AppBoxKitPlatform.supportsComposeM3E) {
      return _withInputTapBehavior(_m3e(context));
    }

    // Fallback (web, or any tier with `wantNative: false`) → Material 3
    // TextField. Plain themed field; carries a filled surface only when a
    // `fillColor` is supplied.
    return _withInputTapBehavior(_material(context));
  }

  /// The per-input dismissal default (see [AppBoxKitInputTapBehavior]) — one
  /// wrap, all three tiers, so every host and scaffolded app gets it by
  /// construction. Region wraps the FULL tier bounds (the CN capsule / M3E
  /// container / Material decoration), not just the editable box, so taps on
  /// the field's padding are inside the group too.
  Widget _withInputTapBehavior(Widget tier) => AppBoxKitInputTapBehavior(
        dismissOnOutsideTap: dismissKeyboardOnOutsideTap,
        child: tier,
      );

  Widget _m3e(BuildContext context) {
    // M3E owns its filled container shape + size via tokens, so the Material
    // styling params (fillColor/borderRadius/tint/text/placeholder colors) don't
    // apply here — same as the CN tier ignores them. `enabled` is honored; a
    // disabled M3E field renders its own disabled state.
    return TextFieldM3E(
      controller: controller,
      placeholder: placeholder ?? hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      autofocus: autofocus,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }

  Widget _material(BuildContext context) {
    final theme = Theme.of(context);
    final underline = BorderSide.none;
    final radius = borderRadius ?? 12.0;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: placeholder ?? hintText,
        filled: fillColor != null,
        fillColor: fillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: underline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: underline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
