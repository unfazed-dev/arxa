import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Feedback-tier card: determinate/indeterminate progress plus the loading
/// indicator (the 3rd tier).
class ShowcaseProgressLoadingCardWidget extends StatelessWidget {
  const ShowcaseProgressLoadingCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Progress & loading'),
          appBoxKitVerticalSpaceSmall,
          Row(
            children: [
              Expanded(
                // ponytail: determinate 0.6 shows the fill; indeterminate
                // circular animates; loading indicator is the 3rd tier.
                child: AppBoxKitNativeProgress.linear(value: 0.6),
              ),
              appBoxKitHorizontalSpaceSmall,
              AppBoxKitNativeProgress.circular(), // factory, not const-able
              appBoxKitHorizontalSpaceSmall,
              const AppBoxKitNativeLoadingIndicator(size: 32),
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
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
