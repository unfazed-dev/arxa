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
      height: axButtonHeightMedium,
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
