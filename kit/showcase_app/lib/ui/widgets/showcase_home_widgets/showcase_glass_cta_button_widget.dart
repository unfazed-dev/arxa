import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Phase 2b (option B): KitNativeButton delegates to CNButton →
/// real Liquid Glass on iOS 26. Height from the kit's button token;
/// width is intrinsic (no magic numbers).
class ShowcaseGlassCtaButtonWidget extends StatelessWidget {
  const ShowcaseGlassCtaButtonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kButtonHeightMedium,
      child: KitNativeButton(
        label: 'Glass CTA',
        glyph: KitGlyphs.star,
        onPressed: () => locator<KitNotificationService>().show(
            'native button tapped',
            position: KitToastPosition.bottom,
            context: context),
      ),
    );
  }
}
