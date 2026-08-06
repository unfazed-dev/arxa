import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_fab_morph.dart';
import 'appbox_kit_menu_item.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// Adaptive FAB that morphs into a menu. On Android it renders
/// `m3e_collection`'s [FabMenuM3E] — a primary FAB that expands a stack of
/// menu items on tap (real Material 3 Expressive motion); everywhere else it
/// delegates to a glass [CNPopupMenuButton], which renders native Liquid Glass
/// on iOS/macOS 26+ and a Cupertino/Material fallback below — so the kit ships
/// genuine native chrome with **no native code of its own**.
///
/// The public surface is **primitives only** ([icon] / [sfSymbol], [items],
/// [onSelect]) so hosts never import either underlying dep. [AppBoxKitMenuItem] is
/// the kit-owned menu vocabulary; each tier maps it to its native menu type
/// ([FabMenuItem] on Android, [CNPopupMenuItem] on Apple).
///
/// [sfSymbol] drives the primary FAB glyph on the Apple tier (native-first);
/// [icon] drives it on Android and is the Apple fallback when [sfSymbol] is
/// null. If both are null the trigger defaults to an add glyph.
class AppBoxKitNativeFabMenu extends StatefulWidget {
  const AppBoxKitNativeFabMenu({
    super.key,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    required this.items,
    this.onSelect,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Paired Material icon + SF Symbol for the primary FAB (see [AppBoxKitGlyphs]).
  /// The preferred way to give the FAB an icon — one token, both tiers.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the primary FAB on the Android tier and the non-native
  /// fallback on the Apple tier. Resolved from the raw `icon` override first,
  /// then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// Native SF Symbol name for the primary FAB on the Apple tier. Preferred
  /// over [icon] there; ignored on Android. Resolved from the raw `sfSymbol`
  /// override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Menu items. Each [AppBoxKitMenuItem] maps to the tier's native menu type.
  final List<AppBoxKitMenuItem> items;

  /// Notified with the selected item. `null` makes the menu display-only on the
  /// Apple tier; on Android items are always tappable (the tier has no per-item
  /// disabled flag).
  final ValueChanged<AppBoxKitMenuItem>? onSelect;

  @override
  State<AppBoxKitNativeFabMenu> createState() => _KitNativeFabMenuState();
}

class _KitNativeFabMenuState extends State<AppBoxKitNativeFabMenu> {
  /// Kit-owned toggle controller for the M3E tier.
  ///
  /// FabMenuM3E wraps [FabMenuM3E.primaryFab] in its own toggle
  /// GestureDetector, but a FabM3E child contains a RawMaterialButton whose
  /// tap recognizer is INNERMOST — and the innermost member wins the gesture
  /// arena sweep. A no-op `onPressed: () {}` therefore swallows every tap and
  /// the menu never opens (verified on emulator-5554: taps were silent).
  /// Routing the FabM3E's own onPressed to this controller keeps the button
  /// enabled (ripple + button semantics) AND performs the toggle itself.
  /// Passing the controller to FabMenuM3E keeps open/close state shared
  /// (scrim tap + popOnItemTap still close via the same controller).
  final FabMenuController _menuController = FabMenuController();

  @override
  void dispose() {
    // FabMenuM3E only disposes controllers it creates itself; this one is ours.
    _menuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Android → real M3 Expressive FAB-menu. Else → glass CNPopupMenuButton,
    // which self-degrades glass → Cupertino → Material.
    if (AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    return _glass(context);
  }

  Widget _m3e(BuildContext context) {
    return FabMenuM3E(
      controller: _menuController,
      // M3E spec: the FAB Menu has NO scrim. The official Compose
      // FloatingActionButtonMenu is a plain in-layout composable (zero
      // Scrim/Popup imports) — the primary FAB itself morphs into the close
      // affordance, so a dimming overlay is wrong here. fab_m3e defaults
      // overlay:true (black α0.25); turn it off.
      overlay: false,
      // AppBoxKitFabMorph (not FabM3E): the primary FAB shape-morphs on press like the
      // kit's icon buttons. FabMenuM3E.primaryFab is Widget-typed, so any morph
      // widget drops in. ponytail: icon defaults to add when no glyph given.
      //
      // Wrapped in an AnimatedBuilder on the shared toggle controller so the
      // glyph cross-fades Add → Close as the menu opens — the signature M3E
      // FAB-Menu morph (Compose flips Add↔Close at the toggle midpoint).
      primaryFab: AnimatedBuilder(
        animation: _menuController,
        builder: (context, _) => AppBoxKitFabMorph(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: RotationTransition(
                turns: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: _menuController.isOpen
                ? const Icon(Icons.close, key: ValueKey('fab-close'))
                : Icon(widget.icon ?? Icons.add,
                    key: const ValueKey('fab-open')),
          ),
          // See _menuController doc: the inner button wins the arena, so IT must
          // toggle — FabMenuM3E's own wrapper GestureDetector never gets the tap.
          onPressed: _menuController.toggle,
        ),
      ),
      // FabMenuItem.onPressed is required-non-null, so each item always carries
      // a closure that forwards to the kit callback (no-op when onSelect null).
      items: [
        for (final item in widget.items)
          FabMenuItem(
            icon: item.icon == null ? const SizedBox.shrink() : Icon(item.icon),
            label: Text(item.label),
            onPressed: () => widget.onSelect?.call(item),
          ),
      ],
    );
  }

  Widget _glass(BuildContext context) {
    // ponytail: native-first — SF Symbol wins on Apple; Material icon is the
    // fallback only when sfSymbol is null. CNPopupMenuButton.icon asserts at
    // least one icon source, so fall back to Icons.add when neither is given.
    // 22pt (not CNSymbol's 24 default): SF Symbols draw ink ~edge-to-edge in
    // the point box (measured live: 24pt config → 24.7pt ink = 0.44 of the
    // 56pt circle). 22pt lands on the ~0.40 Apple-native optical weight for
    // circular buttons. Mirrors AppBoxKitNativeFab's glyph sizing.
    final symbol = widget.sfSymbol == null
        ? null
        // Wire the FAB-menu glyph to the kit accent (mirrors AppBoxKitNativeFab) so
        // the translucent glass trigger carries the theme colour, not a default.
        : CNSymbol(widget.sfSymbol!,
            size: 22, color: Theme.of(context).colorScheme.primary);
    final customIcon =
        widget.sfSymbol == null ? (widget.icon ?? Icons.add) : null;
    return CNPopupMenuButton.icon(
      buttonIcon: symbol,
      buttonCustomIcon: customIcon,
      buttonStyle: CNButtonStyle.glass,
      // FAB spec: 56pt diameter (matches the M3E tier's standard FAB and
      // Apple's prominent floating-action sizing). CNPopupMenuButton.icon
      // defaults to 44pt — toolbar-icon size — which made the FAB render
      // SMALLER than the app-bar buttons it floats above.
      size: 56.0,
      items: [
        for (final item in widget.items)
          CNPopupMenuItem(
            label: item.label,
            icon: item.sfSymbol == null ? null : CNSymbol(item.sfSymbol!),
            customIcon: item.icon,
            isDestructive: item.isDestructive,
          ),
      ],
      // CNPopupMenuButton.onSelected is index-based → map back to the item.
      onSelected: (index) => widget.onSelect?.call(widget.items[index]),
    ).chromeGated();
  }
}
