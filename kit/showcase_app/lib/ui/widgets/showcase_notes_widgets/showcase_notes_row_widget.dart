import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// A single tappable folder-list row: glyph, label, trailing count, chevron.
/// A thin adapter over [KitListTile] (the kit's grouped-list row idiom) so
/// call sites keep passing the count as an int.
class ShowcaseNotesRowWidget extends StatelessWidget {
  const ShowcaseNotesRowWidget({
    super.key,
    required this.glyph,
    required this.label,
    required this.trailingCount,
    required this.onTap,
  });

  final KitGlyph glyph;
  final String label;
  final int trailingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KitListTile(
        glyph: glyph,
        title: label,
        trailingValue: '$trailingCount',
        showChevron: true,
        onTap: onTap,
      );
}
