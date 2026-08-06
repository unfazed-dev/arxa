import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';

/// An icon+label pill chip for capability rails — themed, tappable, fully
/// rounded. Pure-Flutter on every tier — there is **no** native
/// (Liquid-Glass / M3-Expressive) chip surface to wrap, so this widget is
/// named `AppBoxKitChip` (a content widget), **not** `AppBoxKitNativeChip`. See
/// `core/NATIVE_COMPONENTS.md` ("Content widgets").
///
/// The chip is a stadium (fully rounded) [Material] tinted
/// `surfaceContainerHigh` with a minimum height of [axSize36]; the label uses
/// the theme's `labelLarge` and the optional leading [glyph] draws at
/// [axSize18] in `onSurfaceVariant`. A `null` [onTap] renders the same
/// visuals without the ink response (a decorative tag).
///
/// Rows of these scroll inside a `AppBoxKitChipCarousel`; a chip is also fine
/// standalone (a wrap of filter tags, a single capability affordance).
class AppBoxKitChip extends StatelessWidget {
  const AppBoxKitChip({
    super.key,
    required this.label,
    this.glyph,
    this.onTap,
  });

  /// Chip label.
  final String label;

  /// Leading glyph (paired Material icon + SF Symbol; see [AppBoxKitGlyphs]).
  /// `null` = a text-only chip.
  final AppBoxKitGlyph? glyph;

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
          constraints: const BoxConstraints(minHeight: axSize36),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: axPad12,
              vertical: axPad6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (glyph != null) ...[
                  Icon(
                    glyph!.icon,
                    size: axSize18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: axGap6),
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
