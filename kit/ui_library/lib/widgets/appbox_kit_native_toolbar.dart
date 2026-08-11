import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show ToolbarM3E, ToolbarActionM3E;

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// One toolbar action. Primitives only — [label] and/or [icon] (Material glyph,
/// Android / Material tier) / [sfSymbol] (SF Symbol, Apple-native tier) +
/// [onPressed] + [isDestructive] — so hosts never import the underlying toolbar
/// deps. Mirrors [AppBoxKitMenuItem]'s shape: the kit owns the vocabulary, each tier
/// maps it to its native action type (1:1).
class AppBoxKitToolbarAction {
  const AppBoxKitToolbarAction({
    this.label,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    this.onPressed,
    this.isDestructive = false,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Display label. Optional on every tier; pass alongside [glyph] for a
  /// labeled action, omit for an icon-only action.
  final String? label;

  /// Paired Material icon + SF Symbol (see [AppBoxKitGlyphs]). The preferred way to
  /// give an action an icon — one token, both tiers, no drift.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the Android / Material tier. Drives the M3E tier's
  /// [ToolbarActionM3E] (whose `icon` is a required [IconData]); an action with
  /// no [icon] cannot render on the M3E tier and is skipped there. Resolved
  /// from the raw `icon` override first, then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Native SF Symbol name (e.g. `'trash'`) for the Apple-native tier.
  /// Preferred over [icon] there; ignored on Android. Resolved from the raw
  /// `sfSymbol` override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Tap handler. `null` disables the action on every tier.
  final VoidCallback? onPressed;

  /// Destructive action — rendered with the tier's warning styling
  /// ([ColorScheme.error]) on every tier. Drives color mapping per tier.
  final bool isDestructive;

  @override
  String toString() =>
      'AppBoxKitToolbarAction(label: $label, sfSymbol: $sfSymbol, icon: $icon, '
      'isDestructive: $isDestructive)';
}

/// Adaptive top action toolbar — three-tier structural gate (mirrors
/// [AppBoxKitNativeSplitButton]):
/// - **Android M3 Expressive** — [ToolbarM3E] with [actions] mapped 1:1 to
///   [ToolbarActionM3E] (icon + onPressed). This tier delivers REAL M3E toolbar
///   actions — inline action morph + overflow menu — because the kit's primitive
///   [AppBoxKitToolbarAction] is the exact shape [ToolbarActionM3E] accepts.
/// - **iOS 26 Liquid Glass** — [CNGlassButtonGroup]: one [CNButtonData] per
///   [AppBoxKitToolbarAction], blended into a single glass pill via a shared
///   `glassEffectUnionId` (mirrors [AppBoxKitNativeSplitButton._glass]).
///   [isDestructive] → `tint: colorScheme.error`.
/// - **Fallback** (desktop/web, `wantNative: false`) — a rounded Material
///   surface holding a [Row]/[Wrap] of per-action buttons ([IconButton] /
///   [FilledButton.tonal]); [isDestructive] → [ColorScheme.error].
///
/// The public surface is **primitives only** — [AppBoxKitToolbarAction], not `Widget`
/// — so the same 1:1 mapping works on all three tiers. The Android tier
/// ([ToolbarActionM3E]) and the iOS tier ([CNButtonData]) are both data-typed
/// and cannot carry arbitrary host [Widget]s; a `List<Widget>` API (the prior
/// shape) could not honor either. See [AppBoxKitNativeSplitButton] for the same
/// rationale.
class AppBoxKitNativeToolbar extends StatelessWidget {
  const AppBoxKitNativeToolbar({
    super.key,
    required this.actions,
    this.wantNative = true,
    this.height = 44.0,
  });

  /// Trailing actions. Each [AppBoxKitToolbarAction] maps to the tier's native action
  /// type — never an arbitrary [Widget].
  final List<AppBoxKitToolbarAction> actions;

  /// Host opt-out of native chrome.
  final bool wantNative;

  /// Glass pill height on iOS (CNButtonDataConfig.minHeight). Defaults to 44
  /// to match [CNSearchBar]'s default `expandedHeight`. Other tiers size
  /// themselves natively and ignore this.
  final double height;

  @override
  Widget build(BuildContext context) {
    // ponytail: gate order mirrors AppBoxKitNativeSplitButton — M3E first (Android),
    // then Liquid Glass (iOS), else Material fallback.
    if (wantNative && AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    if (wantNative && AppBoxKitPlatform.isIOS) return _glass(context);
    return _fallback(context);
  }

  Widget _m3e(BuildContext context) => ToolbarM3E(
        key: key,
        // ponytail: real M3E actions now — ToolbarActionM3E is icon + onPressed,
        // the exact shape AppBoxKitToolbarAction carries, so the mapping is 1:1.
        // An action with no Material icon (sfSymbol-only) can't build a
        // ToolbarActionM3E (its `icon` is a required IconData) and is skipped.
        actions: [
          for (final a in actions)
            if (a.icon != null)
              ToolbarActionM3E(
                icon: a.icon!,
                onPressed: a.onPressed ?? () {},
                enabled: a.onPressed != null,
                tooltip: a.label,
                label: a.label,
                isDestructive: a.isDestructive,
              ),
        ],
      );

  Widget _glass(BuildContext context) {
    // ponytail: native-first per action — SF Symbol wins on Apple; the Material
    // icon is the fallback only when sfSymbol is null. All actions share one
    // glassEffectUnionId so they blend into a single Liquid Glass pill.
    final scheme = Theme.of(context).colorScheme;
    const union = 'kit-toolbar';
    final config = CNButtonDataConfig(
      style: CNButtonStyle.glass,
      glassEffectUnionId: union,
      minHeight: height,
    );
    return CNGlassButtonGroup(
      buttons: [
        for (final a in actions)
          a.label != null
              ? CNButtonData(
                  label: a.label!,
                  icon: a.sfSymbol == null
                      ? null
                      : CNSymbol(a.sfSymbol!, size: 18.0),
                  customIcon: a.sfSymbol == null ? a.icon : null,
                  onPressed: a.onPressed,
                  tint: a.isDestructive ? scheme.error : null,
                  config: config,
                )
              : CNButtonData.icon(
                  icon: a.sfSymbol == null
                      ? null
                      : CNSymbol(a.sfSymbol!, size: 18.0),
                  customIcon: a.sfSymbol == null ? a.icon : null,
                  onPressed: a.onPressed,
                  tint: a.isDestructive ? scheme.error : null,
                  config: config,
                ),
      ],
    ).chromeGated();
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = [
      for (final a in actions)
        a.label != null
            ? FilledButton.tonal(
                onPressed: a.onPressed,
                style: FilledButton.styleFrom(
                  foregroundColor: a.isDestructive ? scheme.error : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a.icon != null) ...[
                      Icon(a.icon),
                      const SizedBox(width: 8)
                    ],
                    Text(a.label!),
                  ],
                ),
              )
            : IconButton(
                onPressed: a.onPressed,
                icon: Icon(a.icon),
                color: a.isDestructive ? scheme.error : null,
                tooltip: a.label,
              ),
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // Always Wrap, never a count heuristic. `actions.length <= 4 ? Row : …`
        // predicted fit from the number of actions when the constraint is
        // WIDTH: a labelled action is a FilledButton.tonal several times wider
        // than an icon-only IconButton, so three labelled ones ('Share',
        // 'Edit', 'Delete') overflowed a 390pt phone by 92px while passing the
        // `<= 4` test. A Wrap whose content fits lays out exactly like the Row
        // did — one run, same order — so this costs nothing in the common case
        // and simply stops overflowing in the uncommon one.
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          // Forward protection, inert today: measured, both action shapes are
          // 48.0 tall (FilledButton.tonal 144.5×48, IconButton 48×48), so
          // nothing observable changes if this is dropped — a mutation that
          // removes it keeps the suite green. It stays because the Row this
          // replaced defaulted to CENTRE and Wrap defaults to START, so the
          // day an action shape stops being 48 the difference becomes a
          // silent top-alignment regression rather than a caught one.
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }
}
