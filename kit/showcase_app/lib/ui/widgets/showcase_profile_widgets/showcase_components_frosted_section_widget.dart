/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the frosted-surface demo — an explicit
/// ArxaKitFrostedSurface panel (the content-layer glass tier).
///
/// Requirements:
/// 1. [Frosted surface] — browse-the-components-gallery
/// An explicit frosted glass panel with explanatory body text.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; static explanatory text.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_frosted_section_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

/// An explicit ArxaKitFrostedSurface — the ADR 0010 content-layer glass tier.
class ShowcaseComponentsFrostedSectionWidget extends StatelessWidget {
  const ShowcaseComponentsFrostedSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const ArxaKitFrostedSurface(
      padding: EdgeInsets.all(abxSize16),
      child: Text(
        'An explicit ArxaKitFrostedSurface — the ADR 0010 content-layer '
        'glass tier (Flutter-drawn frost: BackdropFilter + tint + rim '
        'highlight). Sheet/dialog bodies and the drawer skin compose '
        'on this same widget.',
      ),
    );
  }
}
