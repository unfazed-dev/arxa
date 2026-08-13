import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_menu_item.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive split button — a primary action segment fused with a chevron that
/// opens a menu. Three tiers:
///
/// - **Android** → `m3e_collection`'s [SplitButtonM3E] (real Material 3
///   Expressive, shape-morphs on press).
/// - **iOS** → [CNGlassButtonGroup]: the action segment + a native popup
///   chevron, blended into one Liquid Glass pill on iOS 26+ (and a
///   Cupertino/Material fallback below).
/// - **Elsewhere** (macOS/desktop/web) → a Material fallback [Row] of an action
///   button + a [PopupMenuButton].
///
/// The public surface is **primitives only** — the action face is built from
/// [label] and/or [icon] / [sfSymbol], and the menu is [menuItems] of
/// [AppBoxKitMenuItem] — so hosts never import either underlying dep.
///
/// The action face is intentionally **not** a `Widget child`: the Android tier
/// ([SplitButtonM3E]) takes a label + leading icon (no custom child), so a
/// `child` param could not be honored there. Building the face from primitives
/// keeps a 1:1 mapping across all three tiers — see [AppBoxKitNativePopupMenu] for
/// the same rationale.
class AppBoxKitNativeSplitButton extends StatelessWidget {
  const AppBoxKitNativeSplitButton({
    super.key,
    this.label,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    this.onAction,
    required this.menuItems,
    this.onMenuSelected,
    this.menuIcon,
    this.menuSfSymbol,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Action-face label. Renders on every tier; pass alongside [glyph].
  final String? label;

  /// Paired Material icon + SF Symbol for the action face (see [AppBoxKitGlyphs]).
  /// The preferred way to give the face an icon — one token, both tiers.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the action face (Android leading icon + Material/else).
  /// Non-native fallback on the Apple tier when [sfSymbol] is null. Resolved
  /// from the raw `icon` override first, then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Native SF Symbol name for the action face on the Apple tier. Preferred
  /// over [icon] there; ignored on Android. Resolved from the raw `sfSymbol`
  /// override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Primary-action tap handler. `null` disables the action segment.
  final VoidCallback? onAction;

  /// Menu items revealed by the chevron. Each [AppBoxKitMenuItem] maps to the tier's
  /// native menu type.
  final List<AppBoxKitMenuItem> menuItems;

  /// Notified with the selected menu item.
  final ValueChanged<AppBoxKitMenuItem>? onMenuSelected;

  /// Material glyph for the chevron (Android trailing + Material/else).
  final IconData? menuIcon;

  /// Native SF Symbol name for the chevron on the Apple tier. Defaults to
  /// `'chevron.down'` when both [menuIcon] and [menuSfSymbol] are null.
  final String? menuSfSymbol;

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive split button. iOS → Liquid Glass group.
    // Else → Material Row fallback.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    if (AppBoxKitPlatform.isIOS) return _glass(context);
    return _material(context);
  }

  Widget _m3e(BuildContext context) => SplitButtonM3E<AppBoxKitMenuItem>(
        // M3 menus live on a neutral surface. split_button_m3e paints the
        // DROPDOWN with the button's own fill colour, so the default `filled`
        // emphasis (cs.primary) rendered a garish primary-coloured menu that
        // clashed with the neutral MenuAnchor popup. `elevated` fills from
        // surfaceContainerHigh → the menu inherits the same neutral surface as
        // the popup, and the button stays a solid raised pill. (The package
        // couples menu colour to emphasis; this is the API-level fix. Switch to
        // `tonal`/`outlined` if a different button weight is wanted.)
        emphasis: SplitButtonM3EEmphasis.elevated,
        label: label,
        leadingIcon: icon,
        onPressed: onAction,
        // SplitButtonM3EItem.child accepts a plain String (wrapped in Text()
        // internally) — verified against split_button_m3e 0.2.1.
        items: [
          for (final item in menuItems)
            SplitButtonM3EItem<AppBoxKitMenuItem>(
              value: item,
              child: item.label,
            ),
        ],
        onSelected: onMenuSelected,
      );

  Widget _glass(BuildContext context) {
    // The split-button composition now lives in cupertino_native_better as
    // CNSplitButton (one CNGlassButtonGroup with a union-synced popup half).
    // This tier only maps kit primitives onto it and wires the kit accent so
    // the glass glyphs never fall back to the iOS system blue in any host.
    //
    // Known CN-fallback limitation: on iOS < 26 (Flutter fallback path) a
    // LABELED action segment renders its icon+label Row in a shrink-wrapped box
    // that can overflow by a few px (CNGlassButtonGroup forces shrinkWrap on its
    // data buttons). Native iOS 26+ renders correctly. Surface only if a host
    // targets labeled split buttons on iOS < 26.
    final scheme = Theme.of(context).colorScheme;
    // Native Liquid Glass everywhere, including scrollables — button-class
    // controls are on the informed allowlist (ratified 2026-08-13, see
    // docs/liquid-glass-allowlist.md §2).
    return CNSplitButton(
      label: label,
      icon: sfSymbol == null
          ? null
          : CNSymbol(sfSymbol!, size: 18.0, color: scheme.primary),
      customIcon: sfSymbol == null ? icon : null,
      onAction: onAction,
      items: [
        for (final item in menuItems)
          // Same mapping as AppBoxKitNativeFabMenu: SF Symbol wins on Apple, the
          // Material icon is the fallback; destructive renders natively red.
          CNButtonDataPopupItem(
            label: item.label,
            sfSymbol: item.sfSymbol,
            customIcon: item.sfSymbol == null ? item.icon : null,
            isDestructive: item.isDestructive,
          ),
      ],
      onSelected: (index) => onMenuSelected?.call(menuItems[index]),
      menuIcon: menuSfSymbol == null
          ? (menuIcon == null
              ? CNSymbol('chevron.down', size: 18.0, color: scheme.primary)
              : null)
          : CNSymbol(menuSfSymbol!, size: 18.0, color: scheme.primary),
      customMenuIcon: menuSfSymbol == null ? menuIcon : null,
    ).chromeGated();
  }

  Widget _material(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _materialAction(context),
        PopupMenuButton<AppBoxKitMenuItem>(
          icon: Icon(menuIcon ?? Icons.arrow_drop_down),
          tooltip: label ?? 'More options',
          itemBuilder: (context) => [
            for (final item in menuItems)
              PopupMenuItem<AppBoxKitMenuItem>(
                value: item,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 20,
                        color: item.isDestructive
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      item.label,
                      style: item.isDestructive
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
          ],
          onSelected: onMenuSelected,
        ),
      ],
    );
  }

  Widget _materialAction(BuildContext context) {
    if (label != null && icon != null) {
      return FilledButton.tonalIcon(
        onPressed: onAction,
        icon: Icon(icon, size: 18),
        label: Text(label!),
      );
    }
    if (label != null) {
      return FilledButton.tonal(
        onPressed: onAction,
        child: Text(label!),
      );
    }
    return IconButton.filled(
      onPressed: onAction,
      icon: Icon(icon ?? Icons.check),
    );
  }
}
