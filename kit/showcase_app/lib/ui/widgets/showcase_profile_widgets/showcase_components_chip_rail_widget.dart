import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Snapping capability rail — [KitChipCarousel] of [KitChip]s, each
/// toasting its label.
class ShowcaseComponentsChipRailWidget extends StatelessWidget {
  const ShowcaseComponentsChipRailWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      locator<KitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return KitChipCarousel(
      snap: true,
      children: [
        for (final (glyph, label) in [
          (KitGlyphs.home, 'Home'),
          (KitGlyphs.search, 'Search'),
          (KitGlyphs.notes, 'Notes'),
          (KitGlyphs.camera, 'Camera'),
          (KitGlyphs.mic, 'Voice'),
          (KitGlyphs.share, 'Share'),
          (KitGlyphs.edit, 'Edit'),
          (KitGlyphs.star, 'Star'),
          (KitGlyphs.tag, 'Tag'),
          (KitGlyphs.settings, 'Settings'),
        ])
          KitChip(
            glyph: glyph,
            label: label,
            onTap: () => _toast(context, label),
          ),
      ],
    );
  }
}
