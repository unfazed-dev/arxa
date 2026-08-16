import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassEffect, LiquidGlassConfig, LiquidGlassContainer;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'appbox_kit_frosted_surface.dart';
import 'appbox_kit_input_tap_behavior.dart' show abxInputTapGroupId;
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
/// would double-draw the glass — the bar draws no capsule of its own. By
/// default ([opaqueGlass]) it does paint a flat opaque base behind the row
/// (tint token at alpha 1.0, platform-view-safe — the action slots are CN
/// platform views) so content never scrolls visibly through the bar; pass
/// `opaqueGlass: false` for the old fully transparent backing.
///
/// ## Action taps never dismiss
///
/// The bar is ONE input surface: its [leading]/[trailing] action slots sit in
/// the same tap-region group as the field ([abxInputTapGroupId]), so tapping
///  or the mic while the keyboard is up keeps the keyboard (the iOS
/// Messages idiom) — the tap classifies as INSIDE, never as an outside tap.
/// Taps outside the whole bar still run the per-input dismissal default
/// ([AppBoxKitInputTapBehavior]). Standalone [AppBoxKitNativeIconButton]s
/// elsewhere in an app deliberately do NOT join the group — only this bar's
/// own slots are part of the input surface.
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
    this.multiline = true,
    this.minLines = 1,
    this.maxLines = 6,
    this.autofocus = false,
    this.enabled = true,
    this.wantNative = true,
    this.opaqueGlass = true,
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

  /// Composer contract (default `true`): the field is a growing multiline
  /// input — one line at rest, growing with content to [maxLines], then
  /// scrolling internally. `false` restores the single-line search-style bar
  /// (the historical behavior).
  final bool multiline;

  /// Minimum visible lines when [multiline] (default 1 = one line at rest).
  final int? minLines;

  /// Maximum lines before the field scrolls internally (default 6, the
  /// chat-composer idiom). Ignored when [multiline] is false.
  final int? maxLines;

  /// Autofocus on appearance.
  final bool autofocus;

  /// Whether the field accepts input (action buttons gate themselves on a
  /// null `onPressed`).
  final bool enabled;

  /// Host opt-out of native chrome, forwarded to the field (`false` forces the
  /// Material [TextField] tier everywhere — the path widget tests take). The
  /// action buttons self-gate per platform like every `AppBoxKitNative*` sibling.
  final bool wantNative;

  /// Opaque flat base behind the bar (default `true`): the tint token at
  /// alpha 1.0 on the platform-view-safe frosted branch (no BackdropFilter
  /// saveLayer — [leading]/[trailing] are CN platform views, and a saveLayer
  /// cannot span the frame slices UiKitViews create, flutter#175048). The
  /// base wraps the bottom [SafeArea] so the home-indicator strip is painted
  /// too. `false` restores the fully transparent bar.
  final bool opaqueGlass;

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
    // The row (field + action slots + its padding) joins the input tap group:
    // action taps are INSIDE the input surface and never dismiss the keyboard
    // (class docs § Action taps never dismiss). Nested same-group regions are
    // the documented TapRegion shape — all members act as one region.
    final Widget bar = TextFieldTapRegion(
      groupId: abxInputTapGroupId,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: abxPad12, vertical: abxPad8),
        child: Row(
          // Composer alignment: when multiline, the field grows UPWARD from the
          // bottom row of actions (Messages idiom) — CrossAxisAlignment.end keeps
          // every action pinned at the field's last line. Single-line bars keep
          // the historical centered row.
          crossAxisAlignment:
              multiline ? CrossAxisAlignment.end : CrossAxisAlignment.center,
          spacing: abxGap8,
          children: [
            ...leading,
            Expanded(
              child: AppBoxKitNativeTextField(
                controller: controller,
                hintText: hintText,
                keyboardType: keyboardType,
                minLines: multiline ? minLines : null,
                maxLines: multiline ? maxLines : 1,
                autofocus: autofocus,
                enabled: enabled,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                wantNative: wantNative,
                // Material-fallback capsule: the CN/M3E tiers own their pill
                // shape and ignore both params (see class docs § Pill shape).
                fillColor: scheme.surfaceContainerHigh,
                borderRadius: abxRad28,
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
    // Keyboard riding (class docs § Keyboard riding): viewInsets padding lifts
    // the bar onto the keyboard; SafeArea covers the home indicator. The two
    // never stack — MediaQuery.padding bottoms out at 0 once the keyboard
    // consumes the inset.
    // Opaque base wraps the SafeArea (so the home-indicator strip is painted)
    // but sits INSIDE the viewInsets padding (so the whole surface lifts onto
    // the keyboard with the bar).
    // PLAIN native anchor (same mechanism as the floating bar's title pill):
    // the bar floats over a platform-view-bearing scrollable, and the
    // engine's view slicer (flow/view_slicer.cc) keeps Flutter ops above the
    // platform views only while they intersect a platform-view rect —
    // otherwise the opaque base drops to the difference-clipped background
    // canvas and passing native glass renders OVER it, reading as a
    // translucent bar. The stationary platform view under the surface holds
    // the intersection every frame. `plain` renders nothing (clear fill,
    // Glass.identity), so no glass-on-glass stacking can occur; on tiers
    // without native glass the vendor container degrades to its bare child.
    // transition-exempt: this container is the PLAIN anchor above — it mounts
    // a platform view that renders nothing (clear fill), so riding a route
    // slide shows nothing and there is nothing to chrome-gate. Gating it
    // would also defeat its purpose: the anchor must stay mounted during
    // transitions to keep the opaque base hoisted. If the effect ever
    // changes from `plain` to real glass, DELETE this exemption and gate it.
    final Widget backed = opaqueGlass
        ? LiquidGlassContainer(
            config: const LiquidGlassConfig(effect: CNGlassEffect.plain),
            child: AppBoxKitFrostedSurface(
              borderRadius: 0,
              platformViewSafe: true,
              tint: scheme.surfaceContainerLowest.withValues(alpha: 1.0),
              child: SafeArea(top: false, child: bar),
            ),
          )
        : SafeArea(top: false, child: bar);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: backed,
    );
  }
}
