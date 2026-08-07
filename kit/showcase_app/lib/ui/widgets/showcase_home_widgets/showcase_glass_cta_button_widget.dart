/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a glass CTA button demo. It shows a
/// native button at the kit's standard height with a star glyph that fires a
/// toast notification on tap.
///
/// Requirements:
/// 1. [Glass CTA demo]
/// A native button with a glyph that shows a toast on tap.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_home_widgets/showcase_glass_cta_button_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Phase 2b (option B): AppBoxKitNativeButton delegates to CNButton →
/// real Liquid Glass on iOS 26. Height from the kit's button token;
/// width is intrinsic (no magic numbers).
class ShowcaseGlassCtaButtonWidget extends StatelessWidget {
  const ShowcaseGlassCtaButtonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: abxButtonHeightMedium,
      child: AppBoxKitNativeButton(
        label: 'Glass CTA',
        glyph: AppBoxKitGlyphs.star,
        onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>().show(
            'native button tapped',
            position: AppBoxKitToastPosition.bottom,
            context: context),
      ),
    );
  }
}
