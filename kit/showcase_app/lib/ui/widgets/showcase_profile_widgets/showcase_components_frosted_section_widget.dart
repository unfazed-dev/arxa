import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// An explicit KitFrostedSurface — the ADR 0010 content-layer glass tier.
class ShowcaseComponentsFrostedSectionWidget extends StatelessWidget {
  const ShowcaseComponentsFrostedSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const KitFrostedSurface(
      padding: EdgeInsets.all(kSize16),
      child: Text(
        'An explicit KitFrostedSurface — the ADR 0010 content-layer '
        'glass tier (Flutter-drawn frost: BackdropFilter + tint + rim '
        'highlight). Sheet/dialog bodies and the drawer skin compose '
        'on this same widget.',
      ),
    );
  }
}
