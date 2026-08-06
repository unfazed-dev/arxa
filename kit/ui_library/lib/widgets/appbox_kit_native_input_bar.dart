import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'appbox_kit_native_icon_button.dart';
import 'appbox_kit_native_textfield.dart';

/// Adaptive pinned input bar — a composite of [AppBoxKitNativeTextField] with
/// leading/trailing [AppBoxKitNativeIconButton] action slots, reproducing the chat
/// idiom (floating pill bar docked above the keyboard: circular `+` button,
/// capsule field with hint, circular voice button). The bar keeps the native
/// tier of its parts (the field is a Liquid Glass capsule on iOS 26 /
/// [TextFieldM3E] on Android — see [AppBoxKitNativeTextField]'s tier docs), so it is
/// pinned chrome and keeps the `AppBoxKitNative*` name.
///
/// The public surface is **primitives + typed slots** — [leading]/[trailing]
/// take [AppBoxKitNativeIconButton]s, never arbitrary [Widget]s, so the bar's actions
/// stay on the native icon-button tiers. Actions must NOT set
/// [AppBoxKitNativeIconButton.size]: the bar enforces the kit's one-size bar-glyph
/// contract (18pt default, NATIVE_COMPONENTS.md § Glyphs) with a debug assert,
/// keeping leading and trailing optically aligned next to the field.
///
/// ## Pill shape
///
/// The capsule look is assembled, not wrapped: the native field owns its glass
/// capsule on iOS and its M3E container shape on Android; on the Material
/// fallback tier the bar passes a 28pt radius + filled surface so the field
/// reads as the same pill. Drawing another capsule container behind the row
/// would double-draw the glass — the bar itself stays transparent.
///
/// ## Keyboard riding
///
/// The bar rides the keyboard itself: it pads by
/// `MediaQuery.viewInsetsOf(context).bottom` and wraps in a bottom [SafeArea].
/// Since `MediaQuery.padding` already subtracts the view insets, the two never
/// double-count — keyboard open lifts the bar exactly onto the keyboard, closed
/// leaves just the home-indicator inset. Host it as `Scaffold.bottomSheet`, in
/// a `Stack`/`Column` bottom slot, or as `Scaffold.bottomNavigationBar` with
/// `resizeToAvoidBottomInset: false` — with the default `true` a Scaffold
/// bottomNavigationBar already rides the keyboard and the bar's own inset
/// padding would double the lift.
class AppBoxKitNativeInputBar extends StatelessWidget {
  const AppBoxKitNativeInputBar({
    super.key,
    this.controller,
    this.hintText,
    this.leading = const [],
    this.trailing = const [],
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.autofocus = false,
    this.enabled = true,
    this.wantNative = true,
  });

  /// Owns the input text (forwarded to [AppBoxKitNativeTextField.controller]).
  final TextEditingController? controller;

  /// Placeholder text, passed through to [AppBoxKitNativeTextField.hintText].
  final String? hintText;

  /// Actions before the field (e.g. a `AppBoxKitGlyphs.add` attach button). Each
  /// renders at the kit's bar-glyph size; do not set
  /// [AppBoxKitNativeIconButton.size] (debug-asserted).
  final List<AppBoxKitNativeIconButton> leading;

  /// Actions after the field (e.g. `AppBoxKitGlyphs.mic` / `AppBoxKitGlyphs.send`). Same
  /// one-size contract as [leading].
  final List<AppBoxKitNativeIconButton> trailing;

  /// Fired on every keystroke.
  final ValueChanged<String>? onChanged;

  /// Fired on submit (return key).
  final ValueChanged<String>? onSubmitted;

  /// Keyboard type, honored on every field tier.
  final TextInputType? keyboardType;

  /// Autofocus on appearance.
  final bool autofocus;

  /// Whether the field accepts input (action buttons gate themselves on a
  /// null `onPressed`).
  final bool enabled;

  /// Host opt-out of native chrome, forwarded to the field (`false` forces the
  /// Material [TextField] tier everywhere — the path widget tests take). The
  /// action buttons self-gate per platform like every `AppBoxKitNative*` sibling.
  final bool wantNative;

  @override
  Widget build(BuildContext context) {
    // One-size bar-glyph contract (18pt default, NATIVE_COMPONENTS.md
    // § Glyphs). Not a constructor assert — a const constructor's assert must
    // be a potentially-constant expression, so `List.every` can't live there.
    assert(
      leading.every((a) => a.size == null) &&
          trailing.every((a) => a.size == null),
      'AppBoxKitNativeInputBar actions keep the kit bar-glyph size (18pt default) '
      'so leading/trailing stay aligned — omit `size`.',
    );
    final scheme = Theme.of(context).colorScheme;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: axPad12, vertical: axPad8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: axGap8,
        children: [
          ...leading,
          Expanded(
            child: AppBoxKitNativeTextField(
              controller: controller,
              hintText: hintText,
              keyboardType: keyboardType,
              autofocus: autofocus,
              enabled: enabled,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              wantNative: wantNative,
              // Material-fallback capsule: the CN/M3E tiers own their pill
              // shape and ignore both params (see class docs § Pill shape).
              fillColor: scheme.surfaceContainerHigh,
              borderRadius: axRad28,
            ),
          ),
          ...trailing,
        ],
      ),
    );
    // Keyboard riding (class docs § Keyboard riding): viewInsets padding lifts
    // the bar onto the keyboard; SafeArea covers the home indicator. The two
    // never stack — MediaQuery.padding bottoms out at 0 once the keyboard
    // consumes the inset.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: bar),
    );
  }
}
