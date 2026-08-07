/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for a horizontal inset — thin padding that
/// gives full-bleed ListView children their 16dp side margins.
///
/// Requirements:
/// 1. [Side inset]
/// Horizontal padding for full-bleed list children.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; a pure padding wrapper.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_inset_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseComponentsInsetWidget extends StatelessWidget {
  const ShowcaseComponentsInsetWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: abxSize16),
        child: child,
      );
}
