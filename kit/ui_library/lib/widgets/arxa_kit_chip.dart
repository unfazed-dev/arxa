import 'package:flutter/material.dart';

import 'package:arxa_kit_core/common/arxa_kit_app_constants.dart';
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';

import 'arxa_kit_pressable.dart';

/// An icon+label pill chip for capability rails — themed, tappable, fully
/// rounded. Pure-Flutter on every tier — there is **no** native
/// (Liquid-Glass / M3-Expressive) chip surface to wrap, so this widget is
/// named `ArxaKitChip` (a content widget), **not** `ArxaKitNativeChip`. See
/// `core/NATIVE_COMPONENTS.md` ("Content widgets").
///
/// The chip is a stadium (fully rounded) [Material] tinted
/// `surfaceContainerHigh` with a minimum height of [abxSize36]; the label uses
/// the theme's `labelLarge` and the optional leading [glyph] draws at
/// [abxSize18] in `onSurfaceVariant`. Presses via [ArxaKitPressable] (a
/// dim, not Material ink); a `null` [onTap] renders the same visuals without
/// the press affordance (a decorative tag).
///
/// Rows of these scroll inside a `ArxaKitChipCarousel`; a chip is also fine
/// standalone (a wrap of filter tags, a single capability affordance).
class ArxaKitChip extends StatelessWidget {
  const ArxaKitChip({
    super.key,
    required this.label,
    this.glyph,
    this.onTap,
  });

  /// Chip label.
  final String label;

  /// Leading glyph (paired Material icon + SF Symbol; see [ArxaKitGlyphs]).
  /// `null` = a text-only chip.
  final ArxaKitGlyph? glyph;

  /// Tap handler. `null` disables the ink response.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: ArxaKitPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: abxSize36),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: abxPad12,
              vertical: abxPad6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (glyph != null) ...[
                  Icon(
                    glyph!.icon,
                    size: abxSize18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: abxGap6),
                ],
                Text(label, style: textTheme.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
