/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the chip-carousel demo — a snapping
/// AppBoxKitChipCarousel of chips that toast their label on tap.
///
/// Requirements:
/// 1. [Chip carousel] — browse-the-components-gallery
/// A snapping capability rail of chips that toast their label on tap.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; taps toast through the notification service.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_chip_rail_widget.dart
library;

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
