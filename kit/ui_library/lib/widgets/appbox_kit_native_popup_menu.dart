import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_menu_item.dart';
import 'appbox_kit_native_chrome_gate.dart';
import 'appbox_kit_native_icon_button.dart';

/// Adaptive popup menu. On Android it opens a Material [showMenu] popup anchored
/// to the trigger (the SAME route `split_button_m3e` and `PopupMenuButton` use,
/// so the reveal motion matches the split-button menu; M3 styling from the
/// ambient theme); on web it takes that same pure-Flutter [showMenu] tier
/// (cupertino_native_better's version probe reads dart:io `Platform`, which
/// throws on web); everywhere else it delegates to [CNPopupMenuButton], which
/// renders native Liquid Glass on iOS/macOS 26+ and a Cupertino/Material
/// fallback below — so the kit ships genuine native chrome with **no native code
/// of its own**.
///
/// The public surface is **primitives only** — the trigger is built from
/// [label] and/or [icon] / [sfSymbol], and [items] are [AppBoxKitMenuItem]s — so hosts
/// never import either underlying dep. Each tier maps [AppBoxKitMenuItem] to its
/// native menu type ([PopupMenuItem] on Android, [CNPopupMenuItem] on Apple).
///
/// The trigger is intentionally **not** a `Widget child`: the Apple tier
/// ([CNPopupMenuButton]) owns its own trigger (text or icon button) and cannot
/// honor a host-supplied anchor, so a `child` param would be silently dropped
/// on half the tiers. Building the trigger from primitives keeps the surface
/// consistent with [AppBoxKitNativeFab] / [AppBoxKitNativeButton]. [label] renders a text
/// trigger; otherwise an icon trigger built from [icon] / [sfSymbol].
class AppBoxKitNativePopupMenu extends StatelessWidget {
  const AppBoxKitNativePopupMenu({
    super.key,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    this.label,
    required this.items,
    this.onSelect,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Paired Material icon + SF Symbol for the trigger (see [AppBoxKitGlyphs]). The
  /// preferred way to give the trigger an icon — one token, both tiers.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the trigger on the Android tier and the non-native
  /// fallback on the Apple tier. Defaults to [Icons.more_vert] when null.
  /// Resolved from the raw `icon` override first, then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Native SF Symbol name for the trigger on the Apple tier. Preferred over
  /// [icon] there; ignored on Android. Resolved from the raw `sfSymbol`
  /// override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Trigger label. When non-null the trigger is a text button (every tier);
  /// when null the trigger is an icon button built from [icon] / [sfSymbol].
  final String? label;

  /// Menu items. Each [AppBoxKitMenuItem] maps to the tier's native menu type.
  final List<AppBoxKitMenuItem> items;

  /// Notified with the selected item.
  final ValueChanged<AppBoxKitMenuItem>? onSelect;

  @override
  Widget build(BuildContext context) {
    // Android → Material showMenu (matches the split-button menu motion).
    // Web → the same pure-Flutter showMenu tier (CN's version probe throws
    // on web). Else → CNPopupMenuButton, which self-degrades glass →
    // Cupertino → Material.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    if (kIsWeb) return _m3e(context);
    return _glass(context);
  }

  Widget _m3e(BuildContext context) {
    // Use showMenu — the SAME route PopupMenuButton and split_button_m3e use —
    // so the overflow menu shares the exact reveal motion as the split-button
    // menu (vertical unroll + staggered item fade), which is what the design
    // asks for. [_openMenu] then anchors it iOS-style: showMenu picks the
    // horizontal side from the button's screen position (trailing → right-
    // aligned, leading → left-aligned) on its own, and we anchor the vertical
    // BELOW the trigger (flipping ABOVE near the screen bottom) so the menu never
    // overlaps it. The morph icon-button trigger is preserved via [_trigger].
    return _trigger(context, onTap: () => _openMenu(context));
  }

  Future<void> _openMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final OverlayState overlayState = Overlay.of(context);
    final RenderBox overlay =
        overlayState.context.findRenderObject()! as RenderBox;
    final Rect btn =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;

    // iOS-like vertical placement: sit the menu BELOW the trigger with a gap and
    // never overlap it. showMenu on its own places the menu at position.top and
    // only clamps to fit — it never flips — and passing the button's full rect
    // put position.top AT the trigger's top, so the menu covered it. Anchor BELOW
    // (trigger.bottom + gap); flip ABOVE when it wouldn't fit below. Crucially,
    // showMenu (_fitInsideScreen) keeps the menu within `screen − 8 − safeArea`
    // and CLAMPS it UP over the trigger when it overflows, so the fit test uses
    // that SAME bound — a raw `overlay.height − btn.bottom` ignores the bottom
    // nav-bar/safe-area and lets the clamp cause the overlap. estHeight is item
    // count × the M3 single-line row + panel padding (exact for single-line).
    const double gap = 8.0;
    const double screenPad = 8.0; // Flutter's private _kMenuScreenPadding
    final EdgeInsets safe = MediaQuery.paddingOf(overlayState.context);
    final double estHeight = items.length * kMinInteractiveDimension + 16.0;
    final double fitBottom = overlay.size.height - screenPad - safe.bottom;
    final bool below = btn.bottom + gap + estHeight <= fitBottom;
    final double top = below
        ? btn.bottom + gap
        : (btn.top - estHeight - gap)
            .clamp(screenPad + safe.top, double.infinity);
    // Cap the menu to the space on its chosen side so showMenu can't clamp it back
    // over the trigger (it scrolls if taller). This makes overlap STRUCTURALLY
    // impossible even when estHeight is wrong — large display/font scale or
    // multi-line items make the real menu taller than the 48px-per-row estimate,
    // and the flip decision alone can't catch that; the maxHeight can.
    final double maxHeight = below ? fitBottom - top : (btn.top - gap) - top;
    // Horizontal stays edge-aware: left=btn.left, right=overlay.width−btn.right →
    // showMenu right-aligns a trailing trigger, left-aligns a leading one.
    final RelativeRect position = RelativeRect.fromLTRB(
      btn.left,
      top,
      overlay.size.width - btn.right,
      overlay.size.height - top,
    );
    final scheme = Theme.of(context).colorScheme;
    final selected = await showMenu<AppBoxKitMenuItem>(
      context: context,
      position: position,
      constraints: BoxConstraints(maxHeight: maxHeight),
      items: [
        for (final item in items)
          PopupMenuItem<AppBoxKitMenuItem>(
            value: item,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon,
                      size: 20,
                      color: item.isDestructive ? scheme.error : null),
                  const SizedBox(width: 12),
                ],
                Text(item.label,
                    style: item.isDestructive
                        ? TextStyle(color: scheme.error)
                        : null),
              ],
            ),
          ),
      ],
    );
    // No context use after the await → no async-gap lint.
    if (selected != null) onSelect?.call(selected);
  }

  Widget _trigger(BuildContext context, {required VoidCallback onTap}) {
    if (label != null) {
      return TextButton(onPressed: onTap, child: Text(label!));
    }
    // Reuse the kit's morph icon button so the Android overflow trigger
    // shape-morphs on press exactly like the search / app-bar icon buttons.
    // Only reached on the M3E tier (Apple uses _glass), so this always renders
    // IconButtonM3E here.
    return AppBoxKitNativeIconButton(
      icon: icon ?? Icons.more_vert,
      onPressed: onTap,
    );
  }

  Widget _glass(BuildContext context) {
    // ponytail: native-first — SF Symbol wins on Apple; Material icon is the
    // fallback only when sfSymbol is null. CNPopupMenuButton.icon asserts at
    // least one icon source, so fall back to Icons.more_vert when neither given.
    // 18pt matches AppBoxKitNativeIconButton's Apple bar-glyph default (HIG nav-bar
    // scale): CNSymbol's own 24 default rendered the trigger visibly larger
    // than sibling bar icon buttons in the same app bar.
    final symbol = sfSymbol == null
        ? null
        // Wire the trigger glyph to the kit accent (mirrors AppBoxKitNativeIconButton)
        // so the bar button never renders a CN default tint.
        : CNSymbol(sfSymbol!,
            size: 18.0, color: Theme.of(context).colorScheme.primary);
    final customIcon = sfSymbol == null ? (icon ?? Icons.more_vert) : null;
    // Alpha-0 hide the native Liquid Glass trigger during route transitions
    // (+ modal overlays) so it can't leak over a route slide — AppBoxKitNativeChromeGate.
    // Native glass everywhere, including scrollables — button-class controls
    // are on the informed allowlist (ratified 2026-08-13, see
    // docs/liquid-glass-allowlist.md §2).
    if (label != null) {
      return AppBoxKitNativeChromeGate(
        child: CNPopupMenuButton(
          buttonLabel: label!,
          buttonStyle: CNButtonStyle.glass,
          items: _cnItems,
          onSelected: (index) => onSelect?.call(items[index]),
        ),
      );
    }
    return AppBoxKitNativeChromeGate(
      child: CNPopupMenuButton.icon(
        buttonIcon: symbol,
        buttonCustomIcon: customIcon,
        buttonStyle: CNButtonStyle.glass,
        items: _cnItems,
        onSelected: (index) => onSelect?.call(items[index]),
      ),
    );
  }

  List<CNPopupMenuEntry> get _cnItems => [
        for (final item in items)
          CNPopupMenuItem(
            label: item.label,
            icon: item.sfSymbol == null ? null : CNSymbol(item.sfSymbol!),
            customIcon: item.icon,
            isDestructive: item.isDestructive,
          ),
      ];
}
