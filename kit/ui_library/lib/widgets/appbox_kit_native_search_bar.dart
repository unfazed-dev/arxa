import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNSearchBar;
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive search bar — two-way structural gate (mirrors [AppBoxKitNativeTabBar]'s
/// `wantNative && supportsComposeM3E` shape):
/// - **Android M3 Expressive** — the built-in Material 3 [SearchBar]. M3 motion
///   (easing, shape morph) is theme-driven, so the Flutter bar already carries
///   the expressive tokens with no extra widget.
/// - **iOS 26 Liquid Glass** — [CNSearchBar] (real native search field via
///   `cupertino_native_better`).
/// - **Fallback** (desktop/web, Apple < 26, or `wantNative: false`) — Material 3
///   [SearchBar].
///
/// The public surface is **primitives only** so hosts never import either
/// underlying dep.
///
/// ## Optional trailing action
/// Pass [actionLabel] + [onAction] to render a lightweight tier-native text
/// button to the field's right — [TextButton] on the Material tiers, a
/// borderless [CupertinoButton] (primary tint) on iOS. **Generic**: any label
/// ('Cancel', 'Done', 'Filter') + any callback; the kit builds the right native
/// affordance per tier. Default null = no button (the contract every existing
/// caller relies on). The trailing button is rendered outside the field in a
/// [Row], NOT via [CNSearchBar]'s `cancelText` — its cancel is lifecycle-coupled
/// to the expand state, which the kit keeps disabled, so it would never show.
class AppBoxKitNativeSearchBar extends StatelessWidget {
  const AppBoxKitNativeSearchBar({
    super.key,
    this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.actionLabel,
    this.onAction,
    this.wantNative = true,
  });

  /// Placeholder text. Maps to [SearchBar]'s `hintText` and [CNSearchBar]'s
  /// `placeholder` (defaults to `'Search'` on the CN tier).
  final String? hint;

  /// Owns the input text on the Material tiers.
  // ponytail: CNSearchBar drives its own text via `CNSearchBarController`; the
  // kit's TextEditingController can't be bridged without a two-way sync layer,
  // so it is honored on the Material tiers and dropped on the CN glass tier.
  // Expose a CN-controller overload only if a host ever needs CN-tier control.
  final TextEditingController? controller;

  /// Fired on every keystroke. Wired on every tier.
  final ValueChanged<String>? onChanged;

  /// Fired on submit (return / search action). Wired on every tier.
  final ValueChanged<String>? onSubmitted;

  /// Trailing action label. The button renders only when **both** [actionLabel]
  /// and [onAction] are non-null; with either null (the default) the field
  /// renders bare — identical to before. See the class docs for the per-tier
  /// look.
  final String? actionLabel;

  /// Trailing action callback. Paired with [actionLabel]; both must be non-null
  /// for the button to render.
  final VoidCallback? onAction;

  /// Host opt-out of native chrome. `true` (default) routes to the native tier
  /// when the platform supports it.
  final bool wantNative;

  @override
  Widget build(BuildContext context) {
    final isCN = wantNative &&
        AppBoxKitPlatform.supportsLiquidGlass &&
        !AppBoxKitPlatform.supportsComposeM3E;
    final field = isCN ? _cn(context) : _material();
    // No trailing action → bare field, the exact contract both existing callers
    // (notes folder, search showcase) rely on.
    if (actionLabel == null || onAction == null) return field;
    return Row(
      spacing: axGap8,
      children: [
        Expanded(child: field),
        _TrailingAction(
          label: actionLabel!,
          onPressed: onAction!,
          materialTier: !isCN,
        ),
      ],
    );
  }

  Widget _material() => SearchBar(
        key: key,
        controller: controller,
        hintText: hint,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );

  Widget _cn(BuildContext context) => CNSearchBar(
        key: key,
        placeholder: hint ?? 'Search',
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        // Keep the CN-tier cancel channel OFF: its cancel only renders when the
        // bar is expanded (disabled below), and we want the trailing action
        // always-on + generic — rendered by [_TrailingAction], not this slot.
        showCancelButton: false,
        // A non-expandable bar matches the kit's single-line primitive contract;
        // the expandable pill animation is a CN-only affordance we don't expose.
        expandable: false,
        // UISearchBar defaults to systemBlue for the caret/cancel/clear
        // affordances — pin them to the app theme instead.
        tint: Theme.of(context).colorScheme.primary,
      ).chromeGated();
}

/// The generic trailing action button, built per tier — a lightweight text
/// affordance (not a filled/glass capsule, which would look heavy next to a
/// search field). Material tiers use [TextButton] (letting its foreground color
/// drive press/overlay states); iOS uses a borderless [CupertinoButton] in the
/// scheme's primary color — the idiomatic search-bar trailing look on each
/// platform.
//
// ponytail: heights are left natural (TextButton ~40 vs field ~56, button
// centered by Row). The centered, slightly-shorter text button IS the native
// look; force a minSize only if a screenshot shows a baseline gap.
class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.label,
    required this.onPressed,
    required this.materialTier,
  });

  final String label;
  final VoidCallback onPressed;
  final bool materialTier;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (materialTier) {
      // TextButton gives the right ink ripple + primary tint; a heavier filled
      // native button would be wrong next to a search field.
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: color),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color),
      ),
    );
  }
}
