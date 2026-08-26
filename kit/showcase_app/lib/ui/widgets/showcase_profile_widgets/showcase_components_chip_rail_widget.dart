/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the chip-carousel demo — a snapping
/// ArxaKitChipCarousel of chips that toast their label on tap.
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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseComponentsChipRailWidget extends StatelessWidget {
  const ShowcaseComponentsChipRailWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      arxaKitLocator<ArxaKitNotificationService>()
          .show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return ArxaKitChipCarousel(
      snap: true,
      children: [
        for (final (glyph, label) in [
          (ArxaKitGlyphs.home, 'Home'),
          (ArxaKitGlyphs.search, 'Search'),
          (ArxaKitGlyphs.notes, 'Notes'),
          (ArxaKitGlyphs.camera, 'Camera'),
          (ArxaKitGlyphs.mic, 'Voice'),
          (ArxaKitGlyphs.share, 'Share'),
          (ArxaKitGlyphs.edit, 'Edit'),
          (ArxaKitGlyphs.star, 'Star'),
          (ArxaKitGlyphs.tag, 'Tag'),
          (ArxaKitGlyphs.settings, 'Settings'),
        ])
          ArxaKitChip(
            glyph: glyph,
            label: label,
            onTap: () => _toast(context, label),
          ),
      ],
    );
  }
}
