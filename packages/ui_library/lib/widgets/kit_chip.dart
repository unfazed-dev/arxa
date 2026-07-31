import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/kit_app_constants.dart';
import 'package:appbox_kit_core/common/kit_glyphs.dart';

/// An icon+label pill chip for capability rails — themed, tappable, fully
/// rounded. Pure-Flutter on every tier — there is **no** native
/// (Liquid-Glass / M3-Expressive) chip surface to wrap, so this widget is
/// named `KitChip` (a content widget), **not** `KitNativeChip`. See
/// `core/NATIVE_COMPONENTS.md` ("Content widgets").
///
/// The chip is a stadium (fully rounded) [Material] tinted
/// `surfaceContainerHigh` with a minimum height of [kSize36]; the label uses
/// the theme's `labelLarge` and the optional leading [glyph] draws at
/// [kSize18] in `onSurfaceVariant`. A `null` [onTap] renders the same
/// visuals without the ink response (a decorative tag).
///
/// Rows of these scroll inside a `KitChipCarousel`; a chip is also fine
/// standalone (a wrap of filter tags, a single capability affordance).
class KitChip extends StatelessWidget {
  const KitChip({
    super.key,
    required this.label,
    this.glyph,
    this.onTap,
  });

  /// Chip label.
  final String label;

  /// Leading glyph (paired Material icon + SF Symbol; see [KitGlyphs]).
  /// `null` = a text-only chip.
  final KitGlyph? glyph;

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
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kSize36),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kPad12,
              vertical: kPad6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (glyph != null) ...[
                  Icon(
                    glyph!.icon,
                    size: kSize18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: kGap6),
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
