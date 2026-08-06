import 'package:flutter/widgets.dart' show IconData;

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';

/// A single item in a native menu (popup / FAB-menu / split-button).
///
/// Primitives only — [label] + optional [glyph] (paired Material icon +
/// SF Symbol from [AppBoxKitGlyphs]) + [isDestructive] — so hosts never import the
/// underlying menu deps. Mirrors [AppBoxKitTab]'s shape: the kit owns the
/// vocabulary, each tier maps it to its native menu type.
///
/// Prefer [glyph] over the raw [icon] / [sfSymbol] escape hatches: a glyph
/// guarantees the Material icon and SF Symbol always match across tiers.
class AppBoxKitMenuItem {
  const AppBoxKitMenuItem({
    required this.label,
    this.glyph,
    IconData? icon,
    String? sfSymbol,
    this.isDestructive = false,
  })  : _icon = icon,
        _sfSymbol = sfSymbol;

  /// Display label.
  final String label;

  /// Paired Material icon + SF Symbol (see [AppBoxKitGlyphs]). The preferred way to
  /// give an item an icon — one token, both tiers, no drift.
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph for the Android / Material tier. Resolved from the raw
  /// `icon` override first, then [glyph].
  IconData? get icon => _icon ?? glyph?.icon;

  /// SF Symbol name (e.g. `'trash'`) for the Apple-native tier. Resolved from
  /// the raw `sfSymbol` override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  /// Destructive action — rendered with the tier's warning styling (red) on
  /// every tier. Drives color mapping in each menu widget.
  final bool isDestructive;

  @override
  String toString() =>
      'AppBoxKitMenuItem(label: $label, sfSymbol: $sfSymbol, icon: $icon, '
      'isDestructive: $isDestructive)';
}
