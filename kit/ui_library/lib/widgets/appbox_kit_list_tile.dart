import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';

import 'appbox_kit_pressable.dart';

/// A grouped-list row: optional leading glyph, title, optional subtitle, and
/// a trailing slot that takes value text and/or a chevron — or a fully custom
/// trailing widget. Pure-Flutter on every tier — there is **no** native
/// (Liquid-Glass / M3-Expressive) list-row surface, so this widget is named
/// `AppBoxKitListTile` (a content widget), **not** `AppBoxKitNativeListTile`. See
/// `core/NATIVE_COMPONENTS.md` ("Content widgets").
///
/// One idiom covers the three row shapes the kit needs:
/// - **Settings row** — `glyph` + `title` + `trailingValue` +
///   `showChevron: true` + `onTap` (grouped settings lists).
/// - **Menu row** — `glyph` + `title` + `onTap` (drawer menus; no trailing
///   chrome).
/// - **Richer row** — `glyph` + `title` + `subtitle` + a custom [trailing]
///   widget (plugin rows with a trailing action). When [trailing] is set it
///   **replaces** [trailingValue] and the chevron — the row never renders
///   both.
///
/// The tile is transparent and full-bleed: place it inside a
/// [AppBoxKitGlassCard]-backed `AppBoxKitListSection` (which owns the group container,
/// header, and dividers) or inside any card surface directly. The row keeps a
/// minimum height of [abxSize48] and presses via [AppBoxKitPressable] (a dim,
/// not Material ink — ink paints over the glass tiers). A `null` [onTap]
/// renders the same visuals without the press affordance (a label row).
class AppBoxKitListTile extends StatelessWidget {
  const AppBoxKitListTile({
    super.key,
    required this.title,
    this.glyph,
    this.subtitle,
    this.trailingValue,
    this.trailing,
    this.showChevron = false,
    this.onTap,
  });

  /// Primary row label.
  final String title;

  /// Leading glyph (paired Material icon + SF Symbol; see [AppBoxKitGlyphs]).
  /// Drawn at [abxSize20] in `onSurfaceVariant`. `null` = no leading slot.
  final AppBoxKitGlyph? glyph;

  /// Secondary line under [title], in the subdued body style. `null` = a
  /// single-line row.
  final String? subtitle;

  /// Trailing value text (e.g. the current setting), drawn subdued before
  /// the chevron. Ignored when [trailing] is set.
  final String? trailingValue;

  /// Custom trailing widget (a switch, an action button, …). When set it
  /// replaces [trailingValue] and the chevron.
  final Widget? trailing;

  /// Whether to append a [AppBoxKitGlyphs.chevronRight] affordance at the trailing
  /// edge. Ignored when [trailing] is set. Defaults to `false` — menu rows
  /// carry no chevron; settings rows opt in.
  final bool showChevron;

  /// Row tap handler. `null` disables the ink response (label row).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: abxSize48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: abxPad16,
          vertical: abxPad12,
        ),
        child: Row(
          children: [
            if (glyph != null) ...[
              Icon(glyph!.icon, size: abxSize20, color: scheme.onSurfaceVariant),
              const SizedBox(width: abxGap12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else ...[
              if (trailingValue != null)
                Text(
                  trailingValue!,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              if (showChevron)
                Icon(
                  AppBoxKitGlyphs.chevronRight.icon,
                  size: abxSize18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ],
        ),
      ),
    );

    // Press feedback is the kit pressable dim, not Material ink — an ink
    // splash paints over the glass tiers (see AppBoxKitPressable).
    return AppBoxKitPressable(onTap: onTap, child: row);
  }
}
