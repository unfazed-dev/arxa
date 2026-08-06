import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Snapping capability rail — [AppBoxKitChipCarousel] of [AppBoxKitChip]s, each
/// toasting its label.
class ShowcaseComponentsChipRailWidget extends StatelessWidget {
  const ShowcaseComponentsChipRailWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return AppBoxKitChipCarousel(
      snap: true,
      children: [
        for (final (glyph, label) in [
          (AppBoxKitGlyphs.home, 'Home'),
          (AppBoxKitGlyphs.search, 'Search'),
          (AppBoxKitGlyphs.notes, 'Notes'),
          (AppBoxKitGlyphs.camera, 'Camera'),
          (AppBoxKitGlyphs.mic, 'Voice'),
          (AppBoxKitGlyphs.share, 'Share'),
          (AppBoxKitGlyphs.edit, 'Edit'),
          (AppBoxKitGlyphs.star, 'Star'),
          (AppBoxKitGlyphs.tag, 'Tag'),
          (AppBoxKitGlyphs.settings, 'Settings'),
        ])
          AppBoxKitChip(
            glyph: glyph,
            label: label,
            onTap: () => _toast(context, label),
          ),
      ],
    );
  }
}
