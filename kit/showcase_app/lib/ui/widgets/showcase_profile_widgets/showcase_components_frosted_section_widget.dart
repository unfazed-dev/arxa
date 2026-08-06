import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// An explicit AppBoxKitFrostedSurface — the ADR 0010 content-layer glass tier.
class ShowcaseComponentsFrostedSectionWidget extends StatelessWidget {
  const ShowcaseComponentsFrostedSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBoxKitFrostedSurface(
      padding: EdgeInsets.all(abxSize16),
      child: Text(
        'An explicit AppBoxKitFrostedSurface — the ADR 0010 content-layer '
        'glass tier (Flutter-drawn frost: BackdropFilter + tint + rim '
        'highlight). Sheet/dialog bodies and the drawer skin compose '
        'on this same widget.',
      ),
    );
  }
}
