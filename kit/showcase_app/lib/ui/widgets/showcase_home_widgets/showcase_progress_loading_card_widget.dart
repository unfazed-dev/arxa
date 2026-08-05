import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Feedback-tier card: determinate/indeterminate progress plus the loading
/// indicator (the 3rd tier).
class ShowcaseProgressLoadingCardWidget extends StatelessWidget {
  const ShowcaseProgressLoadingCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Progress & loading'),
          verticalSpaceSmall,
          Row(
            children: [
              Expanded(
                // ponytail: determinate 0.6 shows the fill; indeterminate
                // circular animates; loading indicator is the 3rd tier.
                child: KitNativeProgress.linear(value: 0.6),
              ),
              horizontalSpaceSmall,
              KitNativeProgress.circular(), // factory, not const-able
              horizontalSpaceSmall,
              const KitNativeLoadingIndicator(size: 32),
            ],
          ),
        ],
      ),
    )
        // iOS 26 scroll edge effect (ADR 0010): glass content softens
        // where it slides under the floating tab bar — external to this
        // scrollable, so the occlusion is explicit (notes folder view is
        // the exemplar). Content-only: the native chrome demos above
        // (buttons/segmented) are never edge-effected.
        .scrollEdgeEffect(
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
